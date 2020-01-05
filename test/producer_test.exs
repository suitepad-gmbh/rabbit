defmodule Rabbit.ProducerTest do
  use ExUnit.Case, async: false

  alias Rabbit.{Connection, Producer}

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestProducer do
    use Rabbit.Producer

    @impl Rabbit.Producer
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  describe "start_link/3" do
    test "starts producer" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, _producer} = Producer.start_link(TestProducer, connection: connection)
    end

    test "returns error when given bad producer options" do
      {:error, _} = Producer.start_link(TestProducer, connection: "foo")
    end
  end

  describe "stop/1" do
    test "stops producer" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)
      assert :ok = Producer.stop(producer)
      refute Process.alive?(producer)
    end

    test "disconnects the amqp channel" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)

      await_publishing(producer)

      state = GenServer.call(producer, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = Producer.stop(producer)

      :timer.sleep(50)

      refute Process.alive?(state.channel.pid)
    end
  end

  describe "publish/6" do
    test "publishes payload to queue" do
      {:ok, amqp_conn} = AMQP.Connection.open()
      {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
      AMQP.Queue.declare(amqp_chan, "foo", auto_delete: true)
      AMQP.Queue.purge(amqp_chan, "foo")

      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)

      await_publishing(producer)

      assert :ok = Producer.publish(producer, "", "foo", "bar")

      :timer.sleep(50)

      assert 1 = AMQP.Queue.message_count(amqp_chan, "foo")

      AMQP.Queue.purge(amqp_chan, "foo")
    end
  end

  test "will reconnect when connection stops" do
    {:ok, amqp_conn} = AMQP.Connection.open()
    {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
    AMQP.Queue.declare(amqp_chan, "foo", auto_delete: true)

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)

    state = GenServer.call(connection, :state)
    AMQP.Connection.close(state.connection)
    :timer.sleep(50)

    assert :ok = Producer.publish(producer, "", "foo", "bar")

    AMQP.Queue.purge(amqp_chan, "foo")
  end

  test "producer modules use init callback" do
    Process.register(self(), :producer_test)

    defmodule TestProducerTwo do
      use Rabbit.Producer

      @impl Rabbit.Producer
      def init(_type, opts) do
        send(:producer_test, :init_callback)
        {:ok, opts}
      end
    end

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, producer} = Producer.start_link(TestProducerTwo, connection: connection)
    assert_receive :init_callback
  end

  test "producer modules use handle_setup callback" do
    Process.register(self(), :producer_test)

    defmodule TestProducerThree do
      use Rabbit.Producer

      @impl Rabbit.Producer
      def init(_type, opts) do
        {:ok, opts}
      end

      @impl Rabbit.Producer
      def handle_setup(_channel) do
        send(:producer_test, :handle_setup_callback)
        :ok
      end
    end

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, producer} = Producer.start_link(TestProducerThree, connection: connection)
    assert_receive :handle_setup_callback
  end

  def await_publishing(producer) do
    producer
    |> GenServer.call(:state)
    |> case do
      %{channel: nil} ->
        :timer.sleep(10)
        await_publishing(producer)

      _ ->
        :ok
    end
  end
end
