import macros, sequtils

const enumSuffix = "Kind"

iterator tail(a: NimNode): NimNode =
  var first = true
  for x in children(a):
    if not first: yield x
    first = false

proc `&`(n: NimNode, s: string): NimNode {. compileTime .} =
  n.expectKind(nnkIdent)
  result = ident($(n) & s)

proc enumsIn(n: NimNode): seq[NimNode] {. compileTime .} =
  result = @[]
  for c in children(n):
    if c.kind == nnkObjConstr:
      let id = c[0]
      id.expectKind(nnkIdent)
      result.add(id)
    elif c.kind == nnkIdent:
      result.add(c)
    else:
      error("Invalid ADT case: " & $(toStrLit(c)))

proc newEnum(name: NimNode, idents: seq[NimNode]): NimNode {. compileTime .} =
  result = newNimNode(nnkTypeDef).add(
    newNimNode(nnkPragmaExpr).add(name).add(
      newNimNode(nnkPragma).add(ident("pure"))),
    newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for ident in idents:
    choices.add(ident)
  result.add(choices)

proc makeBranch(base: NimNode, n: NimNode): NimNode {. compileTime .} =
  result = newNimNode(nnkOfBranch)
  if n.kind == nnkObjConstr:
    let id = newNimNode(nnkDotExpr).add(base, n[0])
    var list = newNimNode(nnkRecList)
    for e in tail(n):
      e.expectKind(nnkExprColonExpr)
      e.expectMinLen(2)
      list.add(newIdentDefs(e[0], e[1]))
    result.add(id, list)
  elif n.kind == nnkIdent:
    result.add(newNimNode(nnkDotExpr).add(base, n), newNimNode(nnkRecList).add(newNilLit()))
  else:
      error("Invalid ADT case: " & $(toStrLit(n)))

proc defineTypes(e, body: NimNode): NimNode {. compileTime .} =
  e.expectKind(nnkIdent)
  body.expectKind(nnkStmtList)
  # The children of the body should look like object constructors
  #
  #   Circle(r: float)
  #   Rectangle(w: float, h: float)
  #
  # Here we first extract the external identifiers (Circle, Rectangle)
  # that will be the possible values of the kind enum.
  let enumName = ident($(e) & enumSuffix)
  let enumType = newEnum(enumName, enumsIn(body))

  # Then we put the actual type we are defining
  var cases = newNimNode(nnkRecCase).add(newIdentDefs(ident("kind"), enumName))
  for child in children(body):
    cases.add(makeBranch(enumName, child))

  let definedType = newNimNode(nnkTypeDef).add(
    e,
    newEmptyNode(),
    newNimNode(nnkObjectTy).add(
      newEmptyNode(),
      newEmptyNode(),
      newNimNode(nnkRecList).add(cases)
    )
  )

  result = newNimNode(nnkTypeSection)
  result.add(enumType)
  result.add(definedType)

proc defineConstructor(e, n: NimNode): NimNode  {. compileTime .} =
  let base = ident($(e)) & enumSuffix
  if n.kind == nnkObjConstr:
    var params = @[e]
    for c in tail(n):
      c.expectKind(nnkExprColonExpr)
      c.expectMinLen(2)
      params.add(newIdentDefs(c[0], c[1]))

    var constr = newNimNode(nnkObjConstr).add(
      e, newColonExpr(ident("kind"), newNimNode(nnkDotExpr).add(base, n[0])))
    for c in tail(n):
      c.expectKind(nnkExprColonExpr)
      c.expectMinLen(2)
      constr.add(newColonExpr(c[0], c[0]))

    result = newProc(
      name = n[0],
      params = params,
      body = newStmtList().add(constr)
    )
  elif n.kind == nnkIdent:
    var constr = newNimNode(nnkObjConstr).add(
      e, newColonExpr(ident("kind"), newNimNode(nnkDotExpr).add(base, n)))
    result = newProc(
      name = n,
      params = [e],
      body = newStmtList().add(constr)
    )
  else:
      error("Invalid ADT case: " & $(toStrLit(n)))

proc eqFor(e, n: NimNode): NimNode {. compileTime .} =
  let base = ident($(e)) & enumSuffix
  if n.kind == nnkObjConstr:
    result = newNimNode(nnkOfBranch).add(newNimNode(nnkDotExpr).add(base, n[0]))
    var comparisons: seq[NimNode] = @[]

    for c in tail(n):
      comparisons.add(infix(newDotExpr(ident("a"), c[0]), "==", newDotExpr(ident("b"), c[0])))

    let body = foldr(comparisons, infix(a, "and", b))

    result.add(newStmtList(newNimNode(nnkReturnStmt).add(body)))
  elif n.kind == nnkIdent:
    result = newNimNode(nnkOfBranch).add(newNimNode(nnkDotExpr).add(base, n))
    result.add(newStmtList(newNimNode(nnkReturnStmt).add(ident("true"))))
  else:
    error("Invalid ADT case: " & $(toStrLit(n)))


proc defineEquality(tp, body: NimNode): NimNode {. compileTime .} =
  # template compare(content, tp: NimNode) =
  #   proc `==`(a, b: tp): bool =
  #     if a.kind == b.kind: content
  #     else: false
  var condition = newNimNode(nnkCaseStmt).add(newDotExpr(ident("a"), ident("kind")))
  for child in children(body):
    condition.add(eqFor(tp, child))

  var body = newNimNode(nnkIfExpr).add(
    newNimNode(nnkElifBranch).add(
      infix(newDotExpr(ident("a"), ident("kind")), "==", newDotExpr(ident("b"), ident("kind"))),
      condition
    ),
    newNimNode(nnkElse).add(newStmtList(newNimNode(nnkReturnStmt).add(ident("false"))))
  )

  result = newProc(
    name = ident("=="),
    params = [ident("bool"), newIdentDefs(ident("a"), tp), newIdentDefs(ident("b"), tp)],
    body = newStmtList(body)
  )
  # result = getAst(compare(condition, tp))

macro variant*(e: expr, body: stmt): stmt {. immediate .} =
  result = newStmtList(defineTypes(e, body), defineEquality(e, body))

  for child in children(body):
    result.add(defineConstructor(e, child))
  when defined(pattydebug):
    echo toStrLit(result)


proc isObject(tp: NimNode): bool {. compileTime .} =
  (tp.kind == nnkObjectTy) and (tp[1][0].kind != nnkRecCase)

proc isVariant(tp: NimNode): bool {. compileTime .} =
  (tp.kind == nnkObjectTy) and (tp[1][0].kind == nnkRecCase)

proc discriminator(tp: NimNode): NimNode {. compileTime .} =
  if (tp.kind == nnkObjectTy) and (tp[1][0].kind == nnkRecCase): tp[1][0][0]
  else: nil

proc matchSimple(n, sym, tp: NimNode): NimNode {. compileTime .} =
  n.expectKind(nnkCall)
  n.expectMinLen(2)

  let
    obj = n[0]
    statements = n[1]
  statements.expectKind(nnkStmtList)

  # This is the new declaration section
  var decl = newNimNode(nnkLetSection)
  # These are the clauses for the bound variables
  for c in tail(obj):
    c.expectMinLen(2)
    # ignore bindings to _
    if $(c[1]) != "_":
      decl.add(newIdentDefs(c[1], newEmptyNode(), newDotExpr(sym, c[0])))

  # We transform the matching branch
  # into a declaration of bound variables
  # followed by the body, for instance
  #
  # let r = :tmp.r
  # ...
  result = newNimNode(nnkStmtList).add(decl)
  for c in children(statements):
    result.add(c)

proc matchBranch(n, sym, tp: NimNode): NimNode {. compileTime .} =
  let obj = n[0]
  # We have a few cases for obj (the matching part)
  # It could be
  # - a matching clause like Circle(r: r)
  # - a literal (not yet)
  # - a bound or unbound variable (not yet)
  obj.expectKind(nnkObjConstr)
  # This is the thing we dispatch on
  let kindId = obj[0]
  kindId.expectKind(nnkIdent)
  result = newNimNode(nnkOfBranch).add(kindId, matchSimple(n, sym, tp))

proc matchVariant(statements, sym, tp: NimNode): NimNode {. compileTime .} =
  # The node for the dispatch statement
  #
  # case :tmp.kind of:
  # ...
  let disc = discriminator(tp)
  result = newNimNode(nnkCaseStmt).add(newDotExpr(sym, disc))
  for child in children(statements):
    result.add(matchBranch(child, sym, tp))

macro match*(e: typed, statements: untyped): stmt =
  statements.expectKind(nnkStmtList)
  let
    exprType = getType(e)
    isSimpleObject = isObject(exprType)
    isVariantObject = isVariant(exprType)

  # A fresh symbol used to hold the evaluation of e
  let sym = genSym()
  let body = if isSimpleObject: matchSimple(statements[0], sym, exprType)
    else: matchVariant(statements, sym, exprType)

  # The whole thing is translated into a
  # declaration section where our temporary
  # symbol is assigned the value of e,
  # followed by the switch statement constructed
  # above
  result = newStmtList(newLetStmt(sym, e), body)

  when defined(pattydebug):
    echo toStrLit(result)