defmodule Orchestrator.RetryQueue do
  use GenServer
  require Logger
  alias __MODULE__

  @type callback_mfa :: {module(), atom(), list()}
  @type should_retry_mf :: {module(), atom()}
  @type delay_retry_mf :: {module(), atom()}
  @type queue_item :: %{
          callback_mfa: callback_mfa(),
          should_retry_mf: should_retry_mf(),
          delay_retry_mf: delay_retry_mf()
        }

  @type t :: %__MODULE__{
          queue: :queue.queue(queue_item()),
          max_retry: non_neg_integer()
        }

  defstruct [:queue, :max_retry]

  def start_link(args) do
    Logger.info("HELLO start_link")
    name = Keyword.get(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @spec queue(module(), callback_mfa(), should_retry_mf(), delay_retry_mf()) :: :ok
  def queue(server, callback_mfa, should_retry_mf, delay_retry_mf) do
    queue_item = %{
      callback_mfa: callback_mfa,
      should_retry_mf: should_retry_mf,
      delay_retry_mf: delay_retry_mf
    }

    GenServer.cast(server, {:enqueue, queue_item})
  end

  @impl true
  def init(arg) do
    queue = Keyword.get(arg, :queue, :queue.new())
    max_retry = Keyword.get(arg, :max_retry, 5)
    {:ok, %__MODULE__{queue: queue, max_retry: max_retry}}
  end

  @impl true
  def handle_cast({:enqueue, queue_item}, state) do
    Logger.debug(":enqueue called with #{inspect(queue_item)}")
    queue = :queue.in(queue_item, state.queue)
    send(self(), :schedule_dequeue)
    {:noreply, %{state | queue: queue}}
  end

  @impl true
  def handle_info(:schedule_dequeue, state) do
    queue = dequeue_and_send(state)
    {:noreply, %{state | queue: queue}}
  end

  def dequeue_and_send(%RetryQueue{} = state) do
    if :queue.is_empty(state.queue) do
      state.queue
    else
      {{:value, item}, queue} = :queue.out(state.queue)
      result = apply_mfa(item.callback_mfa)
      # Ignore the result of this retry
      retry(result, item, state, apply_mf(item.should_retry_mf, [result]), 1)
      queue
    end
  end

  def retry(result, item, %RetryQueue{} = state, should_retry?, retry_count)
      when should_retry? and retry_count <= state.max_retry do
    Logger.debug("Waiting for delay...")
    apply_mf(item.delay_retry_mf, [result, retry_count])
    Logger.info("Retrying callback #{inspect(item.callback_mfa)}")
    result = apply_mfa(item.callback_mfa)
    should_retry? = apply_mf(item.should_retry_mf, [result])
    Logger.debug("Should retry: #{should_retry?}")
    retry(result, item, state, should_retry?, retry_count + 1)
  end

  def retry(result, _item, _state, _should_retry?, _retry_count) do
    case result do
      {:error, reason} ->
        Logger.error("#{__MODULE__} finished retry with result: #{inspect(reason)}")

      result ->
        Logger.debug("#{__MODULE__} finished retry with result: #{inspect(result)}")
    end
  end

  defp apply_mfa({m, f, a}) do
    apply(m, f, a)
  end

  defp apply_mf({m, f}, a) do
    apply(m, f, a)
  end
end
