defmodule Sample do
  @moduledoc """
  Documentation for `Sample`.
  """

  alias Sample.KitchenSink
  alias Sample.KitchenSink.Helpers
  alias Sample.KitchenSink.Error
  alias Sample.Application

  @doc """
  Hello world.
  """
  def hello do
    :world
  end

  @doc """
  Demonstrates cross-module calls.
  """
  def demo do
    sink = KitchenSink.new("demo")
    sink = KitchenSink.rename(sink, "renamed")
    flat = Helpers.deep_flatten([[1, [2]], [3]])
    {sink, flat}
  end

  def demo_classify(value) do
    KitchenSink.classify(value)
  end

  def demo_error(msg) do
    raise Error, msg
  end
end
