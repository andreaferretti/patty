import macros

iterator tail(a: NimNode): NimNode =
  var first = true
  for x in children(a):
    if not first: yield x
    first = false

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

    obj.expectKind(nnkObjConstr)
    statements.expectKind(nnkStmtList)

    # This is the thing we dispatch on
    let kindId = obj[0]
    kindId.expectKind(nnkIdent)

    # This is the new declaration section
    var decl = newNimNode(nnkLetSection)
    # These are the clauses for the bound variables
    for c in tail(obj):
      child.expectMinLen(2)
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
  # echo treeRepr(result)
  # echo toStrLit(result)

when isMainModule:
  type
    ShapeKind = enum
      Circle, Rectangle
    Shape = object
      case kind: ShapeKind
      of Circle:
        r: float
      of Rectangle:
        w, h: float

  proc makeRect(w, h: float): Shape =
    Shape(kind: Rectangle, w: w, h: h)

  match makeRect(3, 4):
    Circle(r: r):
      echo "circle ", r
    Rectangle(w: a, h: b):
      echo "rectangle ", (a + b)
      echo "it works!"