# common.ncl
#
let int_in_range
  : Number -> Number -> Number -> Bool
  = fun min max value =>
    std.number.is_integer value
    && value >= min
    && value <= max
in
{
  Nullable
    | doc m%"
    contract allowing value to be null or match a contract

    ## Examples

    ```nickel
      let Data = {
         name | String,
         email | Nullable String | default = null,
         age | Nullable std.number.Nat | default = null,
      } in
        [
          { name = "Tori", email = "tori@example.com" },
          { name = "Baloo", age=32 }
        ] | Array Data
      # => [{age=null, email="tori@example.com", name="Tori"}, {age=32, email=null, name="Baloo"}]
    ```
    "%
    = fun Contract =>
      std.contract.custom (fun label value =>
        if value == null then
          'Ok value
        else
          std.contract.check Contract label value
      ),

  Id
    | doc "Object id, usually a uuid"
    = std.contract.from_predicate std.is_string,

  FilePath
    | doc "file system path"
    = std.contract.from_predicate std.is_string,

  IntInRange
    | doc m%"
      contract specifying integer within numeric range

      ## Examples

      ```nickel
        1 | IntInRange 0 5
        # => 1
      ```

      ```nickel
        10 | IntInRange 0 5
        # => error: contract broken by a value
      ```
      "%
    = fun min max =>
      std.contract.from_predicate (int_in_range min max),

  ExtraSettings
    | doc "additional freeform settings that don't fit in typed schema"
    = {
      ..
    },

  Verbosity
    | doc "Logging verbosity levels. Default is 'Info"
    = [|
      # critical / urgent - crash or security incident has occurred or is imminent,
      'Critical,
      # very important mesage for operator, may indicate service disruption or security incident.
      # includes runtime error, misconfiguration, installation failure, and security alerts.
      'Error,
      # Potential problem that does not interrupt service
      'Warning,
      # general informative messages. Includes application progress and status updates.
      'Info,
      # alias for 'Info
      'Notice,
      # for developeres, additional debugging information
      'Debug,
      # line or function-level tracing
      'Trace
    |],

  SystemService
    | doc "common settings for system services"
    = {
      user | String | optional,
      group | String | optional,
      workingDir | FilePath | optional,
      autoStart | Bool | default = true,
    },

  Entity
    | doc "common base structure for a system entity"
    = {
      id | doc "unique entity id" | Id | optional, # FIXME
      kind | doc "tag for object kind" | std.enum.TagOrString | optional, # FIXME
      comment | doc "optional notes about object" | optional,
      tags | doc "optional list of tags" | optional | Array std.enum.TagOrString,
      extra | doc "extra settings" | ExtraSettings | optional,
    },

  # originally from https://github.com/tweag/nickel/blob/9ddda8ac5642b960f21f010943c776e5ee966b4c/core/stdlib/std.ncl#L318
  find_first
    : forall a. (a -> Bool) -> Array a -> [| 'Some a, 'None |]
    | doc m%"
      returns the first element satisfying a predicate

      ## Examples

      ```nickel
        find_first ( fun x => (x>10) ) [ 5, 10, 15, 20 ]
        # => 'Some 15
      ```

      ```nickel
        find_first ( fun x => (x>10) ) [ 1, 2, 3 ]
        # => 'None
      ```
    "%
    = fun pred items =>
      # Our fold function, which just ignores the accumulator and immediately
      # returns an element if it satisfies the predicate. Note that `'Error`
      # (which is the short-circuiting branch) means that we found something.
      let f = fun _acc x => if pred x then 'Error x else 'Ok null in
      std.array.try_fold_left f null items
      |> match {
        'Ok _ => 'None,
        'Error found_val => 'Some found_val,
      },

  getdeep
    | doc m%"
        Traverse into a nested struct to get a value. If the array's terminal value,
        and all its parents, are non-null and non-empty, returns 'Some value,
        otherwise 'None. All elements of the array, other than the last,
        must be either a record or null.

        ## Examples
        ```nickel
          let
             common = import "common.ncl",
             cfg = { settings = { app = { theme = "dark" } } }
          in
          [
            ((common.getdeep [cfg, "settings", "app", "theme"]) == 'Some "dark") | std.test.Assert,
            ((common.getdeep [cfg, "settings", "x"]) == 'None) | std.test.Assert,
          ]
          # => [ true, true ]
        ```
        "%
    = fun arr =>
      let tail =
        std.array.reduce_left
          (fun obj next =>
            if obj != null && !std.record.is_empty obj then
              std.record.get_or next null obj
            else
              null
          )
          arr,
      in
      if tail != null && tail != {} then 'Some tail else 'None,

  getdeep_or
    | doc m%"
       like getdeep, but returns value for the Some case,
       and default_val for the None case."

       ## Examples

       ```nickel
       let
         cfg = { settings = { height = 1024 }}
       in
         getdeep_or 768 [ cfg, "settings", "height" ]
       # => 1024
        ```

       ```nickel
       let
         cfg = { settings = { height = 1024 }}
       in
         getdeep_or 2048 [ cfg, "settings", "width" ]
       # => 2048
        ```
         "%
    = fun default_val arr =>
      getdeep arr
      |> match {
        'Some v => v,
        'None => default_val
      },

  map_rec
    : (Dyn -> { _ : Dyn }) -> ([| 'Some _, 'None |] -> { _ : Dyn })
    | doc m%"
       convert 'Some_ || 'None (e.g., output of getdeep) into a record:
       'Some value is mapped through the provided function, 'None maps to {}.
       ## Examples
       ```nickel
         find_first ( fun user => user.id == 3 ) [
            { name = "alice", id = 1 },
            { name = "bob", id = 2 },
            { name = "carol", id = 3 } ]
            |> map_rec (fun found => { user_name = found.name } )
          # => { user_name = "carol" }
       ```
       ```nickel
         find_first ( fun user => user.id == 5 ) [
            { name = "alice", id = 1 },
            { name = "bob", id = 2 },
            { name = "carol", id = 3 } ]
            |> map_rec (fun found => { user_name = found.name } )
         # => {}
       ```
       ```nickel
         ('Some "alice") |> map_rec (fun x => { name = x })
         # => { name = "alice" }
       ```
       ```nickel
         'None |> map_rec (fun x => { name = x })
         # => {}
       ```
     "%
    = fun mapper => match { 'Some v => (mapper v), 'None => {} },
}
