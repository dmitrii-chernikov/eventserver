defmodule ServerTest do
  use ExUnit.Case
  doctest Server

  setup do
    IO.puts("==========")
    Server.start()
    Array.start()
    :ok
  end

  test "adding an event and waiting for it to time-out" do
    # one client will be not subscribed
    {client_ids, sub_ids, non_sub_ids} = spawn_clients(5, 4)

    assert length(client_ids) == 5
    # need some time for communication between processes
    Process.sleep(100)

    subscribed = Server.clients()

    assert map_size(subscribed) == 4

    subscriber = List.last(sub_ids)
    non_subscriber = List.first(non_sub_ids)
    event_name = "event testing firing"

    # adding an event with 0 timeout
    Array.add(subscriber, event_name, "", 0)
    # there should be no error yet
    assert Array.get_last_error(subscriber) == nil
    # adding a valid event
    Array.add(subscriber, event_name, "", 500)
    # there should be no error yet
    assert Array.get_last_error(subscriber) == nil

    events_one = Server.events()
    event_pid = Map.fetch!(events_one, event_name) |> elem(0)
    event_process_name = Utilities.get_process_name(event_pid)

    assert map_size(events_one) == 1
    assert Process.alive?(event_pid)
    assert Enum.member?(Process.registered(), event_process_name)
    # wait for the event to time-out
    Process.sleep(500)

    events_empty = Server.events()

    # the event fired, its info is no longer on the server
    assert map_size(events_empty) == 0
    # all subscribed clients received the "done" signal
    check_last_done(sub_ids, {event_name, ""})
    # the non-subscriber didn't receive the "done" signal
    assert Array.get_last_done(non_subscriber) == nil
    # the event process is dead and unregistered
    assert dead_and_unregistered?(event_pid)
  end

  test "adding an invalid event" do
    # one client will not be subscribed
    {_client_ids, sub_ids, non_sub_ids} = spawn_clients(2, 1)
    subscriber = List.first(sub_ids)
    non_subscriber = List.first(non_sub_ids)
    event_name = "event testing invalid"

    # adding a valid event from a non-subscriber
    Array.add(non_subscriber, event_name, "", 500)
    # need some time for communication between processes
    Process.sleep(100)

    not_subscribed = Array.get_last_error(non_subscriber)

    assert not_subscribed == {:error, :not_subscribed}
    # adding a valid event
    Array.add(subscriber, event_name, "", 200)
    # trying to add a second event with the same name
    Array.add(subscriber, event_name, "desc", 5_000)
    # need some time for communication between processes
    Process.sleep(100)

    name_exists = Array.get_last_error(subscriber)

    assert name_exists == {:error, :name_exists}
    # adding an event with a negative timeout
    Array.add(subscriber, event_name, "", -500)
    # need some time for communication between processes
    Process.sleep(100)

    invalid_timeout = Array.get_last_error(subscriber)

    assert invalid_timeout == {:error, :invalid_timeout}
    # adding an event with an empty name
    Array.add(subscriber, "", "", 500)
    # need some time for communication between processes
    Process.sleep(100)

    invalid_name = Array.get_last_error(subscriber)

    assert invalid_name == {:error, :invalid_name}
  end

  test "adding an event and cancelling it" do
    # one client will not be subscribed
    {client_ids, sub_ids, non_sub_ids} = spawn_clients(3, 2)
    client_first = List.first(sub_ids)
    client_last = List.last(sub_ids)
    non_subscriber = List.first(non_sub_ids)
    event_name = "event testing cancelling"

    # adding a valid event
    Array.add(client_first, event_name, "", 100_000)

    assert Array.get_last_error(client_first) == nil

    events = Server.events()
    event_pid = Map.fetch!(events, event_name) |> elem(0)

    # cancelling from a non-subscriber
    Array.cancel(non_subscriber, event_name)
    # need some time for communication between processes
    Process.sleep(100)

    not_subscribed = Array.get_last_error(non_subscriber)

    assert not_subscribed == {:error, :not_subscribed}
    # cancelling a non-existing event
    Array.cancel(client_first, "non-existing")
    # need some time for communication between processes
    Process.sleep(100)

    not_found = Array.get_last_error(client_first)

    assert not_found == {:error, :event_not_found}
    # another subscriber cancelling the added valid event
    Array.cancel(client_last, event_name)
    assert Array.get_last_error(client_last) == nil
    # no clients received any "done" signals
    check_last_done(client_ids, nil)
    # need some time for communication between processes
    Process.sleep(100)
    # the event process is dead and unregistered
    assert dead_and_unregistered?(event_pid)
  end

  test "shutting down the server" do
    # one client will not be subscribed
    {_client_ids, sub_ids, non_sub_ids} = spawn_clients(3, 2)
    client_first = List.first(sub_ids)
    client_last = List.last(sub_ids)
    non_subscriber = List.first(non_sub_ids)
    event_name = "event testing server down"

    func_check_subscriptions_initial = fn client_pid ->
      ref = Array.subscribed?(client_pid)

      assert ref != nil and ref != :down
    end

    # clients that tried to subscribe, succeeded
    Enum.each(sub_ids, func_check_subscriptions_initial)
    assert Array.subscribed?(non_subscriber) == nil
    # adding a valid event
    Array.add(client_last, event_name, "", 100_000)
    assert Array.get_last_error(client_last) == nil

    events = Server.events()
    event_pid = Map.fetch!(events, event_name) |> elem(0)

    # shutting down from a non-subscriber
    Array.shutdown(non_subscriber)
    # need some time for communication between processes
    Process.sleep(100)

    not_subscribed = Array.get_last_error(non_subscriber)

    assert not_subscribed == {:error, :not_subscribed}
    # shut the server down
    Array.shutdown(client_first)
    # need some time for communication between processes
    Process.sleep(100)

    func_check_subscriptions_down = fn client_pid ->
      assert Array.subscribed?(client_pid) == :down
    end

    # all subscribers saw the server going :down
    Enum.each(sub_ids, func_check_subscriptions_down)
    # the non-subscriber did not "see" it
    assert Array.subscribed?(non_subscriber) == nil
    # the event process is dead and unregistered
    assert dead_and_unregistered?(event_pid)
  end

  test "client going down" do
    {_client_ids, sub_ids, _non_sub_ids} = spawn_clients(2, 2)
    client_first = List.first(sub_ids)
    client_last = List.last(sub_ids)
    client_first_pid = Process.whereis(client_first)
    event_name = "event testing client down"

    # need some time for communication between processes
    Process.sleep(100)

    subscribed_before = Server.clients()

    assert map_size(subscribed_before) == 2
    # adding a valid event
    Array.add(client_last, event_name, "", 500)
    assert Array.get_last_error(client_last) == nil
    # client going down
    Process.exit(client_first_pid, :kill)
    # wait for the event to fire and 100 ms more
    Process.sleep(600)
    check_last_done([client_last], {event_name, ""})

    subscribed_after = Server.clients()

    # server received the 'DOWN' signal and removed
    # the dead client from the list of subscribers
    assert map_size(subscribed_after) == 1
    # client process is dead and unregistered
    assert dead_and_unregistered?(client_first_pid)
  end

  defp spawn_clients(total, subs) when total >= 0 and subs >= 0 do
    Enum.each(1..total, fn _ -> Array.spawn() end)

    client_ids = Map.keys(Array.clients())
    unsubs = total - subs
    subscriber_ids = Enum.take(client_ids, subs)

    Enum.each(subscriber_ids, &Array.subscribe(&1))
    {client_ids, subscriber_ids, Enum.take(client_ids, -unsubs)}
  end

  defp dead_and_unregistered?(pid) do
    name = Utilities.get_process_name(pid)
    registered = Process.registered()

    !Process.alive?(pid) && !Enum.member?(registered, name)
  end

  # expects a list of clients
  defp check_last_done(client_ids, expected) do
    func_last_done = fn pid ->
      assert Array.get_last_done(pid) == expected
    end

    Enum.each(client_ids, func_last_done)
  end
end
