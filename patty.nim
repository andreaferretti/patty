import macros, sequtils

const enumSuffix = "Kind"

iterator tail(a: NimNode): NimNode =
  var first = true
  for x in children(a):
    if not first: yield x
    first = false

proc `&`(n: NimNode, s: string): NimNode =
  n.expectKind(nnkIdent)
  result = ident($(n) & s)

proc expectKinds(n: NimNode, kinds: varargs[NimNodeKind]) =
  if not @kinds.contains(n.kind):
    error("Expected a node of kind among " & $(@kinds) & ", got " & $n.kind, n)

proc getFields(n: NimNode, pub: bool): seq[tuple[name, ty: NimNode]] =
  result = @[]
  var identsWithoutTypeDec: seq[NimNode] = @[]
  for e in tail(n):
    if e.kind == nnkExprColonExpr:
      e.expectMinLen(2)
      let
        fieldName = if pub: postfix(e[0], "*") else: e[0]
        fieldType = e[1]
      for name in identsWithoutTypeDec:
        result.add((name: name, ty: fieldType))
      identsWithoutTypeDec = @[]
      result.add((name: fieldName, ty: fieldType))
    elif e.kind == nnkIdent:
      let name = if pub: postfix(e, "*") else: e
      identsWithoutTypeDec.add(name)
    else:
      error("Invalid feild declaration:" & $(toStrLit(e)))
  if identsWithoutTypeDec.len > 0:
    error("Invalid ADT case: " & $(toStrLit(n)) & n.treeRepr)

proc enumsIn(n: NimNode): seq[NimNode] =
  result = @[]
  for c in children(n):
    if c.kind == nnkObjConstr or c.kind == nnkCall:
      let id = c[0]
      id.expectKind(nnkIdent)
      result.add(id)
    elif c.kind == nnkIdent:
      result.add(c)
    elif c.kind == nnkCommentStmt:
      discard
    else:
      error("Invalid ADT case: " & $(toStrLit(c)))

proc newEnum(name: NimNode, idents: seq[NimNode]): NimNode =
  result = newNimNode(nnkTypeDef).add(
    newNimNode(nnkPragmaExpr).add(name).add(
      newNimNode(nnkPragma).add(ident("pure"))),
    newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for ident in idents:
    choices.add(ident)
  result.add(choices)

proc makeBranch(base, n: NimNode, pub: bool): NimNode =
  result = newNimNode(nnkOfBranch)
  if n.kind == nnkObjConstr or n.kind == nnkCall:
    let id = newNimNode(nnkDotExpr).add(base, n[0])
    var
      list = newNimNode(nnkRecList)
    for field in getFields(n, pub):
      list.add(newIdentDefs(field.name, field.ty))
    result.add(id, list)
  elif n.kind == nnkIdent:
    result.add(newNimNode(nnkDotExpr).add(base, n), newNimNode(nnkRecList).add(newNilLit()))
  elif n.kind == nnkCommentStmt:
    discard
  else:
    error("Invalid ADT case: " & $(toStrLit(n)))

proc makeGenerics(e: NimNode): NimNode =
  e.expectKinds(nnkIdent, nnkBracketExpr)
  if e.kind == nnkIdent:
    result = newEmptyNode()
  else:
    result = newNimNode(nnkGenericParams)
    for i in 1..<e.len:
      result.add(
        newNimNode(nnkIdentDefs).add(
          e[i].copyNimTree,
          newEmptyNode(),
          newEmptyNode()
      ))

proc defineTypes(e, body: NimNode, pub: bool = false): NimNode =
  e.expectKinds(nnkIdent, nnkBracketExpr)
  let typeName =
    if e.kind == nnkIdent: e # non generic case
    else: e[0]               # generic case
  typeName.expectKind(nnkIdent)
  body.expectKind(nnkStmtList)
  # The children of the body should look like object constructors
  #
  #   Circle(r: float)
  #   Rectangle(w: float, h: float)
  #
  # Here we first extract the external identifiers (Circle, Rectangle)
  # that will be the possible values of the kind enum.
  let
    enumName = ident($(typeName) & enumSuffix)
    enumType =
      if pub: newEnum(postfix(enumName, "*"), enumsIn(body))
      else: newEnum(enumName, enumsIn(body))
    tp = if pub: postfix(typeName, "*") else: typeName
    disc = if pub: postfix(ident("kind"), "*") else: ident("kind")

  # Then we put the actual type we are defining
  var cases = newNimNode(nnkRecCase).add(newIdentDefs(disc, enumName))
  for child in children(body):
    if child.kind != nnkCommentStmt:
      cases.add(makeBranch(enumName, child, pub))

  let definedType = newNimNode(nnkTypeDef).add(
    tp,
    makeGenerics(e),
    newNimNode(nnkObjectTy).add(
      newEmptyNode(),
      newEmptyNode(),
      newNimNode(nnkRecList).add(cases)
    )
  )

  result = newNimNode(nnkTypeSection)
  result.add(enumType)
  result.add(definedType)

proc defineConstructor(e, n: NimNode, pub: bool = false): NimNode =
  e.expectKinds(nnkIdent, nnkBracketExpr)
  let typeName =
    if e.kind == nnkIdent: e # non generic case
    else: e[0]               # generic case
  typeName.expectKind(nnkIdent)
  let base = ident($(typeName)) & enumSuffix

  if n.kind == nnkObjConstr or n.kind == nnkCall:
    var params = @[e.copyNimTree]
    for field in getFields(n, false):
      params.add(newIdentDefs(field.name, field.ty))

    var constr = newNimNode(nnkObjConstr).add(
      e.copyNimTree,
      newColonExpr(
        ident("kind"),
        newNimNode(nnkDotExpr).add(base, n[0])
      )
    )
    for field in getFields(n, false):
      constr.add(newColonExpr(field.name, field.name))
    let procName = if pub: postfix(n[0], "*") else: n[0]

    result = newProc(
      name = procName,
      params = params,
      body = newStmtList().add(constr)
    )
    result.pragma = newNimNode(nnkPragma).add(ident("used"))
    result[2] = makeGenerics(e)
  elif n.kind == nnkIdent:
    var constr = newNimNode(nnkObjConstr).add(
      e.copyNimTree, newColonExpr(ident("kind"), newNimNode(nnkDotExpr).add(base, n)))
    let procName = if pub: postfix(n, "*") else: n
    result = newProc(
      name = procName,
      params = [e],
      body = newStmtList().add(constr)
    )
    result.pragma = newNimNode(nnkPragma).add(ident("used"))
    result[2] = makeGenerics(e)
  else:
      error("Invalid ADT case: " & $(toStrLit(n)))

proc eqFor(e, n: NimNode): NimNode =
  e.expectKinds(nnkIdent, nnkBracketExpr)
  let typeName =
    if e.kind == nnkIdent: e # non generic case
    else: e[0]               # generic case
  typeName.expectKind(nnkIdent)
  let base = ident($(typeName)) & enumSuffix
  if n.kind == nnkObjConstr or n.kind == nnkCall:
    result = newNimNode(nnkOfBranch).add(newNimNode(nnkDotExpr).add(base, n[0]))
    var comparisons: seq[NimNode] = @[]

    for c in tail(n):
      # else c.kind == nnkIdent
      let name = if c.kind == nnkExprColonExpr: c[0] else: c
      comparisons.add(infix(newDotExpr(ident("a"), name), "==", newDotExpr(ident("b"), name)))

    let body = foldr(comparisons, infix(a, "and", b))

    result.add(newStmtList(newNimNode(nnkReturnStmt).add(body)))
  elif n.kind == nnkIdent:
    result = newNimNode(nnkOfBranch).add(newNimNode(nnkDotExpr).add(base, n))
    result.add(newStmtList(newNimNode(nnkReturnStmt).add(ident("true"))))
  else:
    error("Invalid ADT case: " & $(toStrLit(n)))


proc defineEquality(tp, body: NimNode, pub: bool = false): NimNode =
  # template compare(content, tp: NimNode) =
  #   proc `==`(a, b: tp): bool =
  #     if a.kind == b.kind: content
  #     else: false
  var condition = newNimNode(nnkCaseStmt).add(newDotExpr(ident("a"), ident("kind")))
  for child in children(body):
    if child.kind != nnkCommentStmt:
      condition.add(eqFor(tp, child))

  var body = newNimNode(nnkIfExpr).add(
    newNimNode(nnkElifBranch).add(
      infix(newDotExpr(ident("a"), ident("kind")), "==", newDotExpr(ident("b"), ident("kind"))),
      condition
    ),
    newNimNode(nnkElse).add(newStmtList(newNimNode(nnkReturnStmt).add(ident("false"))))
  )
  let procName = if pub: postfix(ident("=="), "*") else: ident("==")

  result = newProc(
    name = procName,
    params = [
      ident("bool"),
      newIdentDefs(ident("a"), tp.copyNimTree),
      newIdentDefs(ident("b"), tp.copyNimTree)
    ],
    body = newStmtList(body)
  )
  result.pragma = newNimNode(nnkPragma).add(ident("used"))
  result[2] = makeGenerics(tp)
  # result = getAst(compare(condition, tp))

macro variant*(e, body: untyped): untyped =
  result = newStmtList(defineTypes(e, body), defineEquality(e, body))

  for child in children(body):
    if child.kind != nnkCommentStmt:
      result.add(defineConstructor(e, child))
  when defined(pattydebug):
    echo toStrLit(result)

macro variantp*(e, body: untyped): untyped =
  result = newStmtList(defineTypes(e, body, true), defineEquality(e, body, true))

  for child in children(body):
    if child.kind != nnkCommentStmt:
      result.add(defineConstructor(e, child, true))
  when defined(pattydebug):
    echo toStrLit(result)


###########################################################


proc isObject(tp: NimNode): bool =
  (tp.kind == nnkObjectTy) and (tp[2][0].kind != nnkRecCase)

proc isVariant(tp: NimNode): bool =
  (tp.kind == nnkObjectTy) and (tp[2][0].kind == nnkRecCase)

proc discriminator(tp: NimNode): NimNode =
  if (tp.kind == nnkObjectTy) and (tp[2][0].kind == nnkRecCase): tp[2][0][0]
  else: nil

proc variants(tp: NimNode): seq[NimNode] =
  let disc = discriminator(tp)
  result = @[]
  for e in getType(disc).children:
    if e.kind != nnkEmpty:
      result.add(e)

proc resolveSymbol(id: NimNode, syms: seq[NimNode]): tuple[index: int, sym: NimNode] =
  id.expectKinds(nnkIdent, nnkSym)
  var count = 0
  for sym in syms:
    if $(id) == $(sym):
      return (count, sym)
    count += 1
  error("Invalid matching clause: " & $(id))

proc findBranchContainsIndex(recCase: NimNode, index: int): NimNode =
  for branch in recCase.tail:
    for c in branch.children:
      if c.kind == nnkIntLit and c.intVal == index:
        return branch

proc findFields(tp: NimNode, index: int): seq[NimNode] =
  # ObjectTy
  #   Empty
  #   Empty
  #   RecList
  #     RecCase
  #       Sym "kind"
  #       OfBranch
  #         IntLit 0
  #         RecList
  #           Sym "r"
  #           Sym "x"
  #           Sym "y"
  #       OfBranch
  #         IntLit 1
  #         RecList
  #           Sym "w"
  #           Sym "h"
  #       OfBranch
  #         IntLit 2
  #         RecList
  #           Sym "side"
  #       OfBranch
  #         IntLit 3
  #         IntLit 4
  #         RecList
  #           Sym "a"
  #           Sym "b"
  let
    recCase = tp[2][0]
  result = @[]

  for bc in recCase.findBranchContainsIndex(index):
    if bc.kind == nnkRecList:
      for c in bc:
        result.add(c)

proc findFields(tp: NimNode): seq[NimNode] =
  # ObjectTy
  #   Empty
  #   Empty
  #   RecList
  #     Sym "name"
  #     Sym "surname"
  #     Sym "age"
  let recList = tp[2]
  result = @[]
  for c in recList.children:
    result.add(c)

proc matchWithBindings(statements, sym: NimNode, fields, bindings: seq[NimNode]): NimNode =
  statements.expectKind(nnkStmtList)

  # This is the new declaration section
  var decl = newNimNode(nnkLetSection)
  # These are the clauses for the bound variables
  for i, b in pairs(bindings):
    # ignore bindings to _
    if $(b) != "_":
      decl.add(newIdentDefs(b, newEmptyNode(), newDotExpr(sym, fields[i])))

  # We transform the matching branch
  # into a declaration of bound variables
  # followed by the body, for instance
  #
  # let r = :tmp.r
  # ...
  result = newNimNode(nnkStmtList).add(decl)
  for c in children(statements):
    result.add(c)

proc matchObjectQualified(n, sym, tp: NimNode): NimNode =
  n.expectKind(nnkCall)
  n.expectMinLen(2)

  let
    obj = n[0]
    statements = n[1]
  var
    fields: seq[NimNode] = @[]
    bindings: seq[NimNode] = @[]

  for c in tail(obj):
    c.expectMinLen(2)
    fields.add(c[0])
    bindings.add(c[1])

  return matchWithBindings(statements, sym, fields, bindings)

proc matchObjectImplicit(n, sym, tp: NimNode): NimNode =
  let
    fields = findFields(tp)
    statements = n.last
  var bindings: seq[NimNode] = @[]
  for i in 1 .. len(n) - 2:
    bindings.add(n[i])
  return matchWithBindings(statements, sym, fields, bindings)

proc matchBranchQualified(n, sym, tp: NimNode): NimNode =
  let
    obj = n[0]
    kindId = obj[0]
    (_, kindSym) = resolveSymbol(kindId, variants(tp))
  result = newNimNode(nnkOfBranch).add(kindSym, matchObjectQualified(n, sym, tp))

proc matchBranchImplicit(n, sym, tp: NimNode): NimNode =
  let
    kindId = n[0]
    statements = n.last
  if kindId.kind == nnkIdent and $(kindId) == "_":
    # catch-all pattern
    n.expectLen(2)
    result = newNimNode(nnkElse).add(statements)
  else:
    let
      (index, kindSym) = resolveSymbol(kindId, variants(tp))
      fields = findFields(tp, index)
    var bindings: seq[NimNode] = @[]
    for i in 1 .. len(n) - 2:
      bindings.add(n[i])
    result = newNimNode(nnkOfBranch).add(kindSym, matchWithBindings(statements, sym, fields, bindings))

proc matchObject(n, sym, tp: NimNode): NimNode =
  # We have a few cases for obj (the matching part)
  # It could be
  # - a qualified matching clause like Circle(r: r)
  # - an implicit matching clause like Circle(r)
  # - a literal (not yet)
  # - a bound or unbound variable (not yet)
  if n[0].kind == nnkObjConstr: matchObjectQualified(n, sym, tp)
  else: matchObjectImplicit(n, sym, tp)

proc matchBranch(n, sym, tp: NimNode): NimNode =
  # We have a few cases for obj (the matching part)
  # It could be
  # - a qualified matching clause like Circle(r: r)
  # - an implicit matching clause like Circle(r)
  # - a literal (not yet)
  # - a bound or unbound variable (not yet)
  if n[0].kind == nnkObjConstr: matchBranchQualified(n, sym, tp)
  else: matchBranchImplicit(n, sym, tp)

proc matchVariant(statements, sym, tp: NimNode): NimNode =
  # The node for the dispatch statement
  #
  # case :tmp.kind of:
  # ...
  let disc = discriminator(tp)
  result = newNimNode(nnkCaseStmt).add(newDotExpr(sym, disc))
  for child in children(statements):
    result.add(matchBranch(child, sym, tp))

macro match*(e: typed, body: untyped): untyped =
  let statements =
    if body.kind == nnkDo: body[6]
    else: body
  statements.expectKind(nnkStmtList)
  let
    exprType = getType(e)
    isSimpleObject = isObject(exprType)
    isVariantObject = isVariant(exprType)

  # A fresh symbol used to hold the evaluation of e
  let sym = genSym()
  let body = if isSimpleObject: matchObject(statements[0], sym, exprType)
    else: matchVariant(statements, sym, exprType)

  # The whole thing is translated into a
  # declaration section where our temporary
  # symbol is assigned the value of e,
  # followed by the switch statement constructed
  # above
  result = newStmtList(newLetStmt(sym, e), body)

  when defined(pattydebug):
    echo toStrLit(result)
