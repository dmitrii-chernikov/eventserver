defmodule Utilities do
  def get(process_name, id) do
    send(process_name, {id, self()})
    get_value_from_message(id)
  end

  def server_pid() do
    Process.whereis(:server_loop)
  end

  def array_pid() do
    Process.whereis(:array_loop)
  end

  def pid_to_name(pid, prefix \\ "pid") do
    inspect(pid)
    |> String.replace(~r/[#\.><]/, "")
    |> String.downcase()
    |> String.replace(~r/pid/, prefix)
    |> String.to_atom()
  end

  def get_process_name(pid) do
    Process.info(pid)[:registered_name]
  end

  def get_value_from_message(
        id,
        time \\ 300,
        default \\ :error
      ) do
    receive do
      {^id, value} -> value
      _any -> default
    after
      time -> default
    end
  end

  def kill(name) do
    cond do
      !is_atom(name) ->
        {:error, :not_an_id}

      !Enum.member?(Process.registered(), name) ->
        {:error, :not_found}

      true ->
        Process.exit(Process.whereis(name), :kill)
        Process.unregister(name)
        :ok
    end
  end
end
