# common.ncl
#
{
  # allow value to be null or match a contract
  Nullable = fun Contract =>
    std.contract.custom (fun label value =>
      if value == null then
        'Ok value
      else
        std.contract.check Contract label value
    ),

  # "type alias" for object id
  Id = std.contract.from_predicate std.is_string,

  # "type alias" for os file system path
  FilePath = std.contract.from_predicate std.is_string,

  IntInRange = fun min max =>
    std.contract.from_predicate (fun value =>
      std.number.is_integer value
      && value >= min
      && value <= max
    ),

  ExtraSettings : { _ : Dyn } = {
    ..
  },

  # Logging verbosity levels, in increasing levels of verbosity
  # Generally, default level is 'Info
  Verbosity = [|
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

  # common settings for system services
  SystemService = {
    user | String | optional,
    group | String | optional,
    workingDir | FilePath | optional,
    autoStart | Bool | default = true,
  },

  Entity = {
    id | doc "unique entity id" | Id,
    kind | doc "tag for object kind" | std.enum.TagOrString,
    comment | doc "optional notes about object" | optional,
    tags | doc "optional list of tags" | optional | Array std.enum.TagOrString,
    extra | doc "extra settings" | ExtraSettings | optional,
  },

  # This defines a function that returns the first element satisfying a predicate.
  # from https://github.com/tweag/nickel/blob/9ddda8ac5642b960f21f010943c776e5ee966b4c/core/stdlib/std.ncl#L318
  find_first : forall a. (a -> Bool) -> Array a -> [| 'Some a, 'None |] = fun pred xs =>
    # Our fold function, which just ignores the accumulator and immediately
    # returns an element if it satisfies the predicate. Note that `'Error`
    # (which is the short-circuiting branch) means that we found something.
    let f = fun _acc x => if pred x then 'Error x else 'Ok null in
    std.array.try_fold_left f null xs
    |> match {
      'Ok _ => 'None,
      'Error x => 'Some x,
    },

  # Traverse into a nested struct to get a value. If the array's terminal value,
  # and all its parents, are non-null and non-empty, returns 'Some value, otherwise 'None
  # All elements of the array (other than the last) must be either a record or null
  #
  # Example:
  # ```nickel
  #   let
  #      common = import "common.ncl",
  #      cfg = { settings = { app = { theme = "dark" } } }
  #   in
  #   let tests = [
  #     ((common.getdeep [cfg, "settings", "app", "theme"]) == 'Some "dark") | std.test.Assert,
  #     ((common.getdeep [cfg, "settings", "x"]) == 'None) | std.test.Assert,
  #   ]
  #   in tests
  # ```
  getdeep = fun arr =>
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
  getdeep_or = fun default_val arr =>
    getdeep arr
    |> match {
      'Some v => v,
      'None => default_val
    },

  # convert 'Some_/'None (e.g., output of getdeep) into a record:
  #   'Some value is mapped through the provided function, 'None maps to {}.
  map_rec = fun mapper => match { 'Some v => (mapper v), 'None => {} },
}
