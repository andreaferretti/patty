import macros

dumpTree:
  type
    ListKind {.pure.} = enum
      Nil, Cons
    List[A] = object
      case kind: ListKind
      of ListKind.Nil:
          nil

      of ListKind.Cons:
          head: A
          tail: ref List[A]


  proc `==`[A](a: List[A]; b: List[A]): bool =
    if a.kind == b.kind:
      case a.kind
      of ListKind.Nil:
        return true
      of ListKind.Cons:
        return a.head == b.head and a.tail == b.tail
    else:
      return false

  proc Nil[A](): List[A] =
    List[A](kind: ListKind.Nil)

  proc Cons[A](head: A; tail: ref List[A]): List[A] =
    List[A](kind: ListKind.Cons, head: head, tail: tail)