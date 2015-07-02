import unittest, patty


suite "adt construction":
  test "basic creation":
    adt Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)

    let c = Shape(kind: CircleE, r: 4, x: 2, y: 0)
    check c.r == 4.0

  test "allowing empty objects":
    adt Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)
      UnitCircle

    let r = Shape(kind: RectangleE, w: 2, h: 5)
    check r.h == 5.0

  test "constructor creation":
    adt Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)

    let c = Circle(r = 4, x = 2, y = 0)
    check c.kind == CircleE
    check c.r == 4.0

  test "constructor of constant objects":
    adt Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)
      UnitCircle

    let c = UnitCircle()
    check c.kind == UnitCircleE

suite "pattern matching":
  type
    ShapeKind = enum
      Circle, Rectangle
    Shape = object
      case kind: ShapeKind
      of Circle:
        x, y, r: float
      of Rectangle:
        w, h: float

  test "basic matching":
    let c = Shape(kind: Circle, r: 4, x: 2, y: 0)
    var res: float = 0
    match c:
      Circle(x: x, y: y, r: r):
        res = r
      Rectangle(w: w, h: h):
        res = 1
    check res == 4.0

  test "binding to different variable names":
    let c = Shape(kind: Circle, r: 4, x: 2, y: 0)
    var res: float = 0
    match c:
      Circle(x: x, y: y, r: someNumber):
        res = someNumber
      Rectangle(w: w, h: h):
        res = 1
    check res == 4.0

  test "binding a complex expression":
    proc makeRect(w, h: float): Shape =
      Shape(kind: Rectangle, w: w, h: h)

    var res: float = 0
    match makeRect(3, 4):
      Circle(x: x, y: y, r: r):
        res = r
      Rectangle(w: w, h: h):
        res = w + h
    check res == 7.0

  test "ignoring _ bindings":
    let c = Shape(kind: Circle, r: 4, x: 2, y: 0)
    var res: float = 0
    match c:
      Circle(x: _, y: _, r: r):
        res = r
      Rectangle(w: w, h: h):
        res = w + h
    check res == 4.0