defmodule Orchestrator.CLI do
  def main(args) do
    case check_for_shortcuts(args) do
      :help ->
        display_usage()

      :version ->
        IO.puts("The version...")

      nil ->
        proceed(args)
    end
  end

  defp proceed(args) do
    [task | args] = args
    run_command(task, args)
  end

  defp run_command("login", _args) do
    # TODO: Make this compatible with other platforms
    System.cmd("xdg-open", ["https://metrist.io"])
  end

  defp display_usage do
    IO.puts("""
    Usage: metrist-cli [command]
    Examples:
        metrist-cli login    - Launches the login screen
    """)
  end

  # Check for --help or --version in the args
  defp check_for_shortcuts([arg]) when arg in ["--help", "-h"], do: :help
  defp check_for_shortcuts([arg]) when arg in ["--version", "-v"], do: :version
  defp check_for_shortcuts(_), do: nil
end
