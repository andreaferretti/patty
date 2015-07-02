import macros

const enumSuffix = "E"

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
      result.add(id & enumSuffix)
    elif c.kind == nnkIdent:
      result.add(c & enumSuffix)
    else:
      error("Invalid ADT case: " & $(toStrLit(c)))

proc newEnum(name: NimNode, idents: seq[NimNode]): NimNode {. compileTime .} =
  result = newNimNode(nnkTypeDef).add(name, newEmptyNode())
  var choices = newNimNode(nnkEnumTy).add(newEmptyNode())
  for ident in idents:
    choices.add(ident)
  result.add(choices)

proc makeBranch(n: NimNode): NimNode {. compileTime .} =
  result = newNimNode(nnkOfBranch)
  if n.kind == nnkObjConstr:
    let id = n[0] & enumSuffix
    var list = newNimNode(nnkRecList)
    for e in tail(n):
      e.expectKind(nnkExprColonExpr)
      e.expectMinLen(2)
      list.add(newIdentDefs(e[0], e[1]))
    result.add(id, list)
  elif n.kind == nnkIdent:
    result.add(n & enumSuffix, newNimNode(nnkRecList).add(newNilLit()))
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
    cases.add(makeBranch(child))

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
  if n.kind == nnkObjConstr:
    var params = @[e]
    for c in tail(n):
      c.expectKind(nnkExprColonExpr)
      c.expectMinLen(2)
      params.add(newIdentDefs(c[0], c[1]))

    var constr = newNimNode(nnkObjConstr).add(
      e, newColonExpr(ident("kind"), n[0] & enumSuffix))
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
      e, newColonExpr(ident("kind"), n & enumSuffix))
    result = newProc(
      name = n,
      params = [e],
      body = newStmtList().add(constr)
    )
  else:
      error("Invalid ADT case: " & $(toStrLit(n)))

macro adt*(e: expr, body: stmt): stmt {. immediate .} =
  result = newStmtList(defineTypes(e, body))

  for child in children(body):
    result.add(defineConstructor(e, child))
  when defined(pattydebug):
    echo toStrLit(result)

macro match*(e: expr, body: stmt): stmt {. immediate .} =
  # A fresh symbol used to hold the evaluation of e
  let sym = genSym()
  # The node for the dispatch statement
  #
  # case :tmp.kind of:
  # ...
  var dispatch = newNimNode(nnkCaseStmt)
  dispatch.add(newDotExpr(sym, ident("kind")))

  body.expectKind(nnkStmtList)
  # The children of the body should look like calls
  #
  #   Circle(r: 5):
  #     ...
  #   Rectangle(w: 3, h: 4):
  #     ...
  for child in children(body):
    child.expectKind(nnkCall)
    child.expectMinLen(2)

    # For each child we had an object section
    # for the matching part, and one or more
    # statements to execute
    let
      obj = child[0]
      statements = child[1]

    statements.expectKind(nnkStmtList)

    # We have a few cases for obj (the matchin part)
    # It could be
    # - a matching clause like Circle(r: r)
    # - a literal
    obj.expectKind(nnkObjConstr)

    # This is the thing we dispatch on
    let kindId = obj[0]
    kindId.expectKind(nnkIdent)

    # This is the new declaration section
    var decl = newNimNode(nnkLetSection)
    # These are the clauses for the bound variables
    for c in tail(obj):
      child.expectMinLen(2)
      # ignore bindings to _
      if $(c[1]) != "_":
        decl.add(newIdentDefs(c[1], newEmptyNode(), newDotExpr(sym, c[0])))

    # We transform the matching branch
    # into a declaration of bound variables
    # followed by the body, for instance
    #
    # let r = :tmp.r
    # ...
    var branchBody = newNimNode(nnkStmtList)
    branchBody.add(decl)
    for c in children(statements):
      branchBody.add(c)

    # This is the complete branch in the dispatch
    # statement
    var ofBranch = newNimNode(nnkOfBranch)
    ofBranch.add(kindId)
    ofBranch.add(branchBody)

    dispatch.add(ofBranch)

  # The whole thing is translated into a
  # declaration section where our temporary
  # symbol is assigned the value of e,
  # followed by the switch statement constructed
  # above
  result = newNimNode(nnkStmtList)
  result.add(newLetStmt(sym, e))
  result.add(dispatch)

  when defined(pattydebug):
    echo toStrLit(result)