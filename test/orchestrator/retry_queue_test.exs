defmodule Orchestrator.RetryQueueTest do
  use ExUnit.Case, async: true
  alias Orchestrator.MetristAPI
  alias Orchestrator.RetryQueue

  defmodule QueueWrapper do
    def insert(queue, item) do
      :queue.in(item, queue)
    end
  end

  defmodule Stub do
    def callback({pid, data} = arg) do
      IO.inspect("Callback")
      send(pid, {:callback, data})
      arg
    end

    def retry?({pid, data}) do
      send(pid, {:retry?, data})
      true
    end

    def delay({pid, data}, _retry_count) do
      send(pid, {:delay, data})
    end

    def no_delay({pid, data}, _retry_count) do
      send(pid, {:no_delay, data})
      :ok
    end
  end

  test "Calls the callback methods" do
    q =
      :queue.new()
      |> QueueWrapper.insert(%{
        callback_mfa: {Stub, :callback, [{self(), "a"}]},
        should_retry_mf: {Stub, :retry?},
        delay_retry_mf: {Stub, :no_delay}
      })

    qr = %RetryQueue{
      queue: q,
      max_retry: 1
    }

    q = RetryQueue.dequeue_and_send(qr)
    # Initial call
    assert_received {:callback, "a"}
    # Retries
    assert_received {:retry?, "a"}
    assert_received {:no_delay, "a"}
    assert_received {:callback, "a"}
    assert_received {:retry?, "a"}
    refute_received {:no_delay, "a"}
  end


  test "Retries when Orchestrator.APIClient.retry_api_request?/1 returns true" do
    fourtwonine_resp = {:ok, %HTTPoison.Response{status_code: 429} }
    fivehundred_resp = {:ok, %HTTPoison.Response{status_code: 500} }
    q =
      :queue.new()
      |> QueueWrapper.insert(%{
        callback_mfa: {Stub, :callback, [{self(), fourtwonine_resp}]},
        should_retry_mf: {Stub, :retry?},
        delay_retry_mf: {Stub, :no_delay}
      })
      |> QueueWrapper.insert(%{
        callback_mfa: {Stub, :callback, [{self(), fivehundred_resp}]},
        should_retry_mf: {Stub, :retry?},
        delay_retry_mf: {Stub, :delay}
      })

    qr = %RetryQueue{
      queue: q,
      max_retry: 1
    }

    q = RetryQueue.dequeue_and_send(qr)
    assert_received {:callback, ^fourtwonine_resp}
    assert_received {:retry?, ^fourtwonine_resp }
    assert_received {:no_delay, ^fourtwonine_resp}
    assert_received {:retry?, ^fourtwonine_resp}
    refute_received {:no_delay, ^fourtwonine_resp}

    q = RetryQueue.dequeue_and_send(%{qr | queue: q})
    assert_received {:callback, ^fivehundred_resp}
    assert_received {:retry?, ^fivehundred_resp}
    assert_received {:delay, ^fivehundred_resp}
    assert_received {:retry?, ^fivehundred_resp}
    refute_received {:delay, ^fivehundred_resp}
  end

  test "HELLO" do
    server = Orchestrator.RetryQueue.start_link([])
    Orchestrator.APIClient.write_telemetry("awslambda", "Nice", 1.0)
    |> IO.inspect()
    Process.sleep(:timer.seconds(20))
  end
end
