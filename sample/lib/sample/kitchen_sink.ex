defmodule Sample.KitchenSink do
  @moduledoc """
  A module exercising many Elixir language features for AST exploration.
  """

  use GenServer
  require Logger
  import Enum, only: [map: 2, filter: 2]
  alias Sample.KitchenSink.Helpers

  @behaviour GenServer

  @default_timeout 5_000
  @version "1.0.0"

  @type status :: :idle | :running | :stopped
  @type t :: %__MODULE__{
          name: String.t(),
          status: status(),
          count: non_neg_integer()
        }

  @typep internal_state :: %{buffer: list(), cursor: non_neg_integer()}

  @opaque token :: reference()

  defstruct name: "", status: :idle, count: 0

  # Guards

  defguard is_positive(n) when is_integer(n) and n > 0

  defguardp is_valid_status(s) when s in [:idle, :running, :stopped]

  # Public API

  @doc "Starts the server with the given name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_count(GenServer.server()) :: non_neg_integer()
  def get_count(server) do
    GenServer.call(server, :get_count)
  end

  def increment(server, amount \\ 1)

  def increment(server, amount) when is_positive(amount) do
    GenServer.cast(server, {:increment, amount})
  end

  def increment(_server, _amount) do
    {:error, :invalid_amount}
  end

  @doc """
  Pattern matching on multiple clauses with guards.
  """
  def classify(x) when is_binary(x), do: :string
  def classify(x) when is_integer(x) and x > 0, do: :positive
  def classify(x) when is_integer(x) and x < 0, do: :negative
  def classify(0), do: :zero
  def classify(x) when is_float(x), do: :float
  def classify(x) when is_list(x), do: :list
  def classify(x) when is_map(x), do: :map
  def classify(x) when is_atom(x), do: :atom
  def classify(_), do: :unknown

  # Private functions

  defp do_process(items) when is_list(items) do
    items
    |> filter(&(&1 != nil))
    |> map(&transform/1)
  end

  defp transform({key, value}) when is_atom(key) do
    {key, value * 2}
  end

  defp transform(value) when is_number(value), do: value * 2
  defp transform(value), do: value

  # GenServer callbacks

  @impl GenServer
  def init(opts) do
    state = %{
      name: Keyword.get(opts, :name, "default"),
      count: 0,
      status: :idle,
      buffer: [],
      started_at: DateTime.utc_now()
    }

    Logger.info("KitchenSink started: #{state.name}")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_count, _from, state) do
    {:reply, state.count, state}
  end

  def handle_call({:set_status, status}, _from, state) when is_valid_status(status) do
    {:reply, :ok, %{state | status: status}}
  end

  def handle_call(msg, _from, state) do
    Logger.warning("Unexpected call: #{inspect(msg)}")
    {:reply, {:error, :unknown}, state}
  end

  @impl GenServer
  def handle_cast({:increment, amount}, state) do
    {:noreply, %{state | count: state.count + amount}}
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_info(:timeout, state) do
    Logger.debug("Timeout received")
    {:noreply, %{state | status: :idle}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("KitchenSink terminating: #{inspect(reason)}")
    :ok
  end

  # Macros

  defmacro with_logging(label, do: block) do
    quote do
      Logger.debug("Start: #{unquote(label)}")
      result = unquote(block)
      Logger.debug("End: #{unquote(label)}")
      result
    end
  end

  defmacrop debug_value(expr) do
    quote do
      value = unquote(expr)
      Logger.debug("#{unquote(Macro.to_string(expr))} = #{inspect(value)}")
      value
    end
  end

  # Protocols and behaviours

  defmodule Helpers do
    @moduledoc false

    @doc "Recursively flattens a nested structure."
    def deep_flatten(list) when is_list(list) do
      Enum.flat_map(list, fn
        item when is_list(item) -> deep_flatten(item)
        item -> [item]
      end)
    end

    def identity(x), do: x
  end

  # Exception

  defmodule Error do
    defexception [:message, :code]

    @impl Exception
    def exception({code, msg}) do
      %__MODULE__{message: msg, code: code}
    end

    def exception(msg) do
      %__MODULE__{message: msg, code: :unknown}
    end
  end

  # Comprehensions, with, and complex expressions

  def process_batch(items) do
    for item <- items,
        item != nil,
        transformed = transform(item),
        transformed != :skip,
        reduce: [] do
      acc -> [transformed | acc]
    end
  end

  def fetch_and_process(source, key) do
    with {:ok, data} <- fetch(source),
         {:ok, value} <- Map.fetch(data, key),
         {:ok, result} <- validate(value) do
      {:ok, transform(result)}
    else
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch(:memory), do: {:ok, %{a: 1, b: 2}}
  defp fetch(:disk), do: {:ok, %{x: 10, y: 20}}
  defp fetch(_), do: {:error, :unknown_source}

  defp validate(value) when is_number(value) and value > 0, do: {:ok, value}
  defp validate(_), do: {:error, :invalid}

  # Sigils and interpolation

  def patterns do
    %{
      email: ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
      words: ~w(hello world foo bar),
      template: ~s(Hello #{@version})
    }
  end

  # Try/rescue/after

  def safe_divide(a, b) do
    try do
      result = a / b
      {:ok, result}
    rescue
      ArithmeticError -> {:error, :division_by_zero}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    after
      Logger.debug("Division attempted: #{a} / #{b}")
    end
  end

  # Receive (for illustration)

  def wait_for_message(timeout \\ @default_timeout) do
    receive do
      {:data, payload} -> {:ok, payload}
      :ping -> :pong
      msg -> {:unexpected, msg}
    after
      timeout -> {:error, :timeout}
    end
  end

  # Multi-clause anonymous functions and captures

  def sorter do
    fn
      {_, a}, {_, b} when a < b -> true
      {a, _}, {b, _} -> a <= b
    end
  end

  def apply_to_list(list, fun \\ &transform/1) do
    Enum.map(list, fun)
  end

  # Struct operations and update syntax

  def new(name) do
    %__MODULE__{name: name, status: :idle, count: 0}
  end

  def rename(%__MODULE__{} = sink, new_name) do
    %{sink | name: new_name}
  end

  # Binary pattern matching

  def parse_header(<<version::8, type::8, length::16, payload::binary>>) do
    %{version: version, type: type, length: length, payload: payload}
  end

  def parse_header(_), do: {:error, :invalid_header}

  # ETS interaction example

  def setup_cache(name) do
    :ets.new(name, [:set, :public, :named_table])
  end

  def cache_put(table, key, value, ttl \\ 60) do
    expires_at = System.monotonic_time(:second) + ttl
    :ets.insert(table, {key, value, expires_at})
  end

  # Combined expression showcase

  def process_and_report(items, opts) do
    label = Keyword.get(opts, :label, "batch")
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    filtered =
      items
      |> filter(&(&1 != nil))
      |> map(&transform/1)

    result =
      with {:ok, data} <- fetch(:memory),
           merged = Map.merge(data, %{items: filtered}),
           {:ok, _} <- validate(map_size(merged)) do
        case Keyword.get(opts, :format) do
          :json ->
            {:ok, Jason.encode!(merged)}

          :raw ->
            {:ok, merged}

          nil ->
            {:ok, inspect(merged)}
        end
      else
        {:error, reason} -> {:error, reason}
        :error -> {:error, :unknown}
      end

    status =
      if result == {:ok, _} do
        :success
      else
        :failure
      end

    response =
      receive do
        {:ack, ref} -> {:confirmed, ref}
        :cancel -> :cancelled
      after
        timeout -> :timed_out
      end

    Logger.info("#{label}: #{status}, response: #{inspect(response)}")
    {result, response}
  end

  # Callbacks

  @callback on_event(event :: term(), state :: term()) :: {:ok, term()} | {:error, term()}
  @callback format_output(term()) :: String.t()
end
