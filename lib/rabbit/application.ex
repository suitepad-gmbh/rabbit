defmodule Rabbit.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Rabbit.Config,
      Rabbit.Worker.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Rabbit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
