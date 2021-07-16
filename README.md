# Flex
## Gotchas
- relies on docker executable which must be visible from $PATH
- when using a `docker context` different from the default "default", ensure
  you've created it beforehand.
- before `iex -S mix`, ~~`make` should be fired to populate bin/.~~

## Installation
```elixir
def deps do
  [
    {:flex, git: "git@git.keepinmind.info:extra/flex.git", submodules: true},
  ]
end
```
You're encouraged to also specify a tag.

