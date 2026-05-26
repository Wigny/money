defmodule Money.Application do
  use Application
  require Logger

  def start(_type, args) do
    children = [
      Money.Currency.Store
    ]

    opts =
      if args == [] do
        [strategy: :one_for_one, name: Money.Supervisor]
      else
        args
      end

    supervisor = Supervisor.start_link(children, opts)

    register_custom_currencies()

    supervisor
  end

  @doc false
  def register_custom_currencies do
    case Application.get_env(:ex_money, :custom_currencies) do
      nil ->
        :ok

      currencies when is_list(currencies) ->
        Enum.each(currencies, fn {code, options} ->
          case Money.Currency.new(code, options) do
            {:ok, _currency} ->
              :ok

            {:error, exception} ->
              Logger.warning(
                "Failed to register custom currency #{inspect(code)}: " <>
                  Exception.message(exception)
              )
          end
        end)
    end
  end
end
