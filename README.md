Patty - A pattern matching library
==================================

Patty is a library to perform pattern matching in Nim. The patterns have to be [variant objects](http://nim-lang.org/docs/manual.html#types-object-variants), which in Nim are encoded with a field (usually called `kind`) which varies in an enum, and a different object layout based on the value of this tag. An example would be

```nim
type
  ShapeKind = enum
    Circle, Rectangle
  Shape = object
    case kind: ShapeKind
    of Circle:
      r: float
    of Rectangle:
      w, h: float
```

If you have such an algebraic data type, you can do the following with Patty:

```nim
import patty

proc makeRect(w, h: float): Shape = Shape(kind: Rectangle, w: w, h: h)

match makeRect(3, 4):
  Circle(r: radius):
    echo "it is a circle of radius ", radius
  Rectangle(w: width, h: height):
    echo "it is a rectangle of height ", height
```

This will be translated by the `match` macro into the following form

```nim
let :tmp = makeRect(3, 4)
case :tmp.kind
of Circle:
  let radius = :tmp.r
  echo "it is a circle of radius ", radius
of Rectangle:
  let
    width = :tmp.w
    height = :tmp.h
  echo "it is a rectangle of height ", height
```

Matching by position is also valid, like this:

```nim
match makeRect(3, 4):
  Circle(radius):
    echo "it is a circle of radius ", radius
  Rectangle(width, height):
    echo "it is a rectangle of height ", height
```

One can also use `_` for a variable, in which case it will not be bound. That is, the following

```nim
import patty

proc makeRect(w, h: float): Shape = Shape(kind: Rectangle, w: w, h: h)

match makeRect(3, 4):
  Circle(r: radius):
    echo "it is a circle of radius ", radius
  Rectangle(w: _, h: height):
    echo "it is a rectangle of height ", height
```

becomes

```nim
let :tmp = makeRect(3, 4)
case :tmp.kind
of Circle:
  let radius = :tmp.r
  echo "it is a circle of radius ", radius
of Rectangle:
  let height = :tmp.h
  echo "it is a rectangle of height ", height
```

Notice that in the examples, the field you dispatch on is called `kind`, but any other name would do. Also, checks are exhaustive: if you miss a case, the compiler will complain.

One can instead pattern-match on non-variant objects, which essentially amounts to deconstructing fields:

```nim
type Person = object
  name: string
  age: int
let p = Person(name: "John Doe", age: 37)
match p:
  Person(name: n, age: a):
    echo n, "is ", a, " years old"
```

Again, this is the same as

```nim
match p:
  Person(n, a):
    echo n, "is ", a, " years old"
```

Constructing variant objects
----------------------------

Patty also provides another macro to create algebraic data types. It looks like

```nim
variant Shape:
  Circle(r: float)
  Rectangle(w: float, h: float)
  UnitCircle
```

and expands to

```nim
type
  ShapeKind {.pure.} = enum
    Circle, Rectangle, UnitCircle
  Shape = object
    case kind: ShapeKind
    of ShapeKind.Circle:
      r: float
    of ShapeKind.Rectangle:
      w: float
      h: float
    of ShapeKind.UnitCircle:
      nil

proc `==`(a: Shape; b: Shape): bool =
  if a.kind == b.kind:
    case a.kind
    of ShapeKind.Circle:
      return a.r == b.r
    of ShapeKind.Rectangle:
      return a.w == b.w and a.h == b.h
    of ShapeKind.UnitCircle:
      return true
  else:
    return false

proc Circle(r: float; x: float; y: float): Shape =
  Shape(kind: ShapeKind.Circle, r: r)

proc Rectangle(w: float; h: float): Shape =
  Shape(kind: ShapeKind.Rectangle, w: w, h: h)

proc UnitCircle(side: int): Shape =
  Shape(kind: ShapeKind.UnitCircle)
```

Notice that the macro also generates three convenient constructors (`Circle` ,`Rectangle` and `UnitCircle`), and in fact the enum is pure to avoid a name conflict. Also, a proper definition of equality based on the actual contents of the record is generated.

**By default the generated ADT is private to the module**. If you want to generate a public ADT use the `variantp` macro, which has the same syntax as `variant` but makes the types, fields, equality definition and generated constructors public.

A couple of limitations fo the `variant` macro:

* field names must be unique across branches (that is, different variants cannot have two fields with the same name). This is actually a limitation of Nim.
* the shortcut that groups field names by type does not seem to work, that is, in the above example one could not write `Rectangle(w, h: float)`.

In the future, Patty may also add copy constructors. Also, some work needs to be done to make it easier to use the generated contructors with `ref` types, in particular for the important case of recursive algebraic data types.

Things that do not work (yet)
-----------------------------

One would expect many forms of pattern matching but, at least for now, the support in Patty is very limited. Things that would be nice to support but do not work yet include:

* matching a constant

```nim
match c:
  "hello":
    echo "the string was hello"
```

* matching an existing variable

```nim
let x = 5
match c:
  x:
    echo "c == 5"
```

* nested pattern matching

```nim
match c:
  Circle(Point(x: x, y: y), r: r):
    echo "the abscissa of the center is ", x
```

* matching without binding

```nim
match c:
  Circle:
    echo "it is a circle!"
```

* binding subpatterns

```nim
match getMeACircle():
  c@Circle(x, y, r):
    echo "there you have ", c
```

* pattern matching as an expression

```nim
let coord = match c:
  Circle(x: x, y: y, r: r):
    x
  Rectangle(w: w, h: h):
    h
```

* unification

```nim
match r:
  Rectangle(w: x, h: x):
    echo "it is a square"
```

* guards

```nim
match c:
  Circle(x: x, y: y, r: r) if r < 0:
    echo "the circle has negative length"
```

* variable-length pattern matching, such as with arrays

```nim
match c:
  [a, b, c]:
    echo "the length is 3 and the first elements is ", a
```

* custom pattern matchers, such as in regexes

```nim
let Email = r"(\w+)@(\w+).(\w+)"
match c:
  Email(name, domain, tld):
    echo "hello ", name
```

* combining patterns with `or`

```nim
match c:
  Circle or Rectangle:
    echo "it is a shape"
```