mode = ScriptMode.Verbose

version       = "0.1.10"
author        = "Andrea Ferretti"
description   = "Algebraic data types and pattern matching"
license       = "Apache2"
skipFiles     = @["test", "test.nim", "testhelp.nim"]

requires "nim >= 0.14.0"


task tests, "run tests":
  --hints: off
  --linedir: on
  --stacktrace: on
  --linetrace: on
  --debuginfo
  --path: "."
  --run
  setCommand "c", "test.nim"

task test, "run tests":
  setCommand "tests"