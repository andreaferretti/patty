import unittest, patty, testhelp

proc `~`[A](a: A): ref A =
  new(result)
  result[] = a

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

  test "variant types with documentation comments":
    variant Shape:
      ## This is a shape
      Circle(r: float, x: float, y: float)
      Rectangle(w: float, h: float)
      Square(side: int)
      ## This is a constant object
      UnitCircle

    let c = UnitCircle()
    check c.kind == ShapeKind.UnitCircle

  test "recursive types":
    variant IntList:
      Nil
      Cons(head: int, tail: ref IntList)

    let d = Cons(3, ~(Cons(2, ~(Cons(1, ~(Nil()))))))
    check d.head == 3
    check d.tail.head == 2

  test "generic types":
    # There is a conflict with later types due to Nim bug:
    # https://github.com/nim-lang/Nim/issues/5170
    variant List2[A]:
      Nil
      Cons(head: A, tail: ref List2[A])

    var d = Cons(3, ~(Cons(2, ~(Cons(1, ~(Nil[int]()))))))
    check d.head == 3
    check d.tail.head == 2

    # Check that equality behaves as expected
    let nilInt = ~(Nil[int]())
    let nilString = ~(Nil[string]())
    check: Cons(123, nilInt) == Cons(123, nilInt)
    check: Cons(321, nilInt) != Cons(123, nilInt)
    check: Cons("foo", nilString) == Cons("foo", nilString)

  test "generic types with multiple parameters":
    variant Either[A, B]:
      Left(a: A)
      Right(b: B)

    match Left[int, string](123):
      Left(a):
        check: a == 123
      Right(b):
        check: false

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

  test "one type declaration to multiple fields":
    variant Shape:
      Circle(r: float, x, y: float)
      Rectangle(w, h: float)
      Square(side: int)
      UnitCircle

    let
      c = Circle(3, 2, 5)
      r = Rectangle(4, 2)
      s = Square(42)

    check c.r == 3
    check c.x == 2
    check c.y == 5
    check r.w == 4
    check r.h == 2
    check s.side == 42

  test "handling visibility":
    let car = Vehicle(kind: VehicleKind.Car, brand: "Fiat", model: "Punto")

    check car.brand == "Fiat"

  test "handling visibility in equality":
    let
      car1 = Vehicle(kind: VehicleKind.Car, brand: "Fiat", model: "Punto")
      car2 = Vehicle(kind: VehicleKind.Car, brand: "Fiat", model: "Punto")

    check car1 == car2

  test "handling visibility in constructors":
    let
      car1 = Car(brand = "Fiat", model = "Punto")
      car2 = Car(brand = "Fiat", model = "Punto")
      bike = Bycicle()
      truck = Truck(length = 12, tires = 8)

    check car1 == car2
    check truck.kind == VehicleKind.Truck
    check bike.kind == VehicleKind.Bycicle
    check truck.tires == 8

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
   Person = object
     name, surname: string
     age: int
   FruitKind = enum
     Apple, Pear
   Fruit = object
     case fruit: FruitKind
     of Apple:
       radius, weight: float
     of Pear:
       circumference, height: float

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

 test "matching a simple object":
   let c = Person(name: "Andrea", surname: "Ferretti", age: 34)
   var res: string = ""
   match c:
     Person(name: n, surname: s, age: a):
       res = n
   check res == "Andrea"

 test "basic matching with a different discriminator":
   let a = Fruit(fruit: Apple, radius: 4, weight: 200)
   var res: float = 0
   match a:
     Apple(radius: r, weight: w):
       res = w
     Pear(circumference: c, height: h):
       res = 1
   check res == 200.0

 test "matching a type generated by the variant macro":
   variant Shape:
     Circle(r: float, x: float, y: float)
     Rectangle(w: float, h: float)
     Square(side: int)
   let c = Circle(3, 5, 6)
   var res: float = 0
   match c:
     Circle(r: r, x: x, y: y):
       res = r
     Rectangle(w: w, h: h):
       res = 1
     Square(side: s):
       res = 1
   check res == 3.0

 test "matching a variant type with implicit field names":
   let c = Shape(kind: Circle, x: 2, y: 0, r: 4)
   var res: float = 0
   match c:
     Circle(x, y, r):
       res = r
     Rectangle(w, h):
       res = 1
   check res == 4.0

 test "matching a variant type with implicit field names using other identifiers":
   let c = Shape(kind: Circle, x: 2, y: 0, r: 4)
   var res: float = 0
   match c:
     Circle(x, y, radius):
       res = radius
     Rectangle(width, height):
       res = 1
   check res == 4.0

 test "matching as an expression":
   let c = Shape(kind: Circle, x: 2, y: 0, r: 4)
   let res = match c:
     Circle(x, y, radius):
       radius
     Rectangle(width, height):
       1.0
   check res == 4.0

 test "matching a simple object with implicit fields names":
   let c = Person(name: "Andrea", surname: "Ferretti", age: 34)
   var res: string = ""
   match c:
     Person(name, surname, age):
       res = name
   check res == "Andrea"

 test "matching a simple object with implicit fields names using other identifiers":
   let c = Person(name: "Andrea", surname: "Ferretti", age: 34)
   var res: string = ""
   match c:
     Person(n, s, a):
       res = n
   check res == "Andrea"

 test "catch-all pattern":
   let c = Shape(kind: Rectangle, w: 4, h: 3)
   var res: float = 0
   let debug = true
   match c:
     Circle(x: _, y: _, r: r):
       res = r
     _:
       res = 13
   check res == 13.0

 test "matching on a generic type":
   type
     ListKind = enum Nil, Cons
     List[A] = object
       case disc: ListKind
       of Nil:
         discard
       of Cons:
         head: A
         tail: ref List[A]

   proc `<>`[A](x: A, xs: List[A]): List[A] =
     List[A](disc: Cons, head: x, tail: ~xs)

   proc listHelper[A](xs: seq[A]): List[A] =
     if xs.len == 0: List[A](disc: Nil)
     else: xs[0] <> listHelper(xs[1 .. xs.high])

   proc list[A](xs: varargs[A]): List[A] = listHelper(@xs)

   let x = list(1, 2, 3)
   var res = 0
   match x:
     Cons(head, tail):
       res = head
     Nil:
       res = 5

   check(res == 1)

 test "generic variant":
   type AccProc[T] = proc(): T {.nimcall.}

   variant Accept[T]:
     NotAcc
     Acc(fun: AccProc[T])

   discard Acc[int](nil)

 test "matching inside generic context":
   variant Foo:
     mkA

   proc bar[T](t: T): int =
     let m = mkA()
     result = 0
     match m:
       mkA:
         result = 1
   check(bar(1) == 1)

 test "matching with a variant which share some fields with other variants":
   type XKind {.pure.} = enum
     A
     B

   type X = object
     case kind: XKind
     of A, B:
       x: int

   let
     x: X = X(kind: XKind.A, x: 0)
     y: X = X(kind: XKind.B, x: 42)

   proc test_match(x :X): int =
     match x:
       A(x): return x
       B(x): return x

   check(test_match(x) == 0)
   check(test_match(y) == 42)
