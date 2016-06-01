mode = ScriptMode.Verbose

version       = "0.1.8"
author        = "Andrea Ferretti"
description   = "Algebraic data types and pattern matching"
license       = "Apache2"
skipFiles     = @["test", "test.nim", "testhelp.nim"]

requires "nim >= 0.11.2"


task tests, "run tests":
  --hints: off
  --linedir: on
  --stacktrace: on
  --linetrace: on
  --debuginfo
  --path: "."
  --run
  setCommand "c", "test"