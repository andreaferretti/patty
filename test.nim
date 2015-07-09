import unittest, patty, macros


suite "variant construction":
  test "basic creation":
    variant Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)

    let c = Shape(kind: ShapeKind.Circle, r: 4, x: 2, y: 0)
    check c.r == 4.0

  test "allowing empty objects":
    variant Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)
      UnitCircle

    let r = Shape(kind: ShapeKind.Rectangle, w: 2, h: 5)
    check r.h == 5.0

  test "constructor creation":
    variant Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)

    let c = Circle(r = 4, x = 2, y = 0)
    check c.kind == ShapeKind.Circle
    check c.r == 4.0

  test "constructor of constant objects":
    variant Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)
      UnitCircle

    let c = UnitCircle()
    check c.kind == ShapeKind.UnitCircle

  test "recursive types":
    variant IntList:
      Nil
      Cons(head: int, tail: ref IntList)

    proc inew[A](a: A): ref A =
      new(result)
      result[] = a

    var d = Cons(3, inew(Cons(2, inew(Cons(1, inew(Nil()))))))
    check d.head == 3
    check d.tail.head == 2

  test "generated equality":
    variant Shape:
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)
      UnitCircle

    let
      c1 = Circle(r = 3, x = 2, y = 5)
      c2 = Circle(r = 3, x = 2, y = 5)
      c3 = Circle(r = 2, x = 3, y = 5)
      s = Square(3)
      u1 = UnitCircle()
      u2 = UnitCircle()
    check c1 == c2
    check c1 != c3
    check c1 != s
    check u1 == u2

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
