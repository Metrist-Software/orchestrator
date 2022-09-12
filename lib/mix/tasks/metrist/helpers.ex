defmodule Mix.Tasks.Metrist.Helpers do
  def do_parse_args(args, definitions, aliases, required) do
    {opts, []} =
      OptionParser.parse!(
        args,
        strict: definitions,
        aliases: aliases
      )

    missing =
      required
      |> Enum.filter(fn opt -> is_nil(opts[opt]) end)

    if length(missing) > 0, do: raise("Missing required option(s): #{inspect(missing)}")

    IO.inspect(opts, label: "Parsed options")

    {opts, []}
  end
end
