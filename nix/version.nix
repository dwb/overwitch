# Single source of truth: the version declared in configure.ac.
builtins.head (
  builtins.match ".*AC_INIT\\(\\[overwitch],\\[([^]]+)].*" (builtins.readFile ../configure.ac)
)
