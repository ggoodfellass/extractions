defmodule Extractions do

  def start do
    start_date = Calendar.DateTime.from_erl!({{2019, 10, 2},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    end_date = Calendar.DateTime.from_erl!({{2019, 12, 2},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")

    interval = 1200

    all_days = Calendar.Date.days_after_until(start_date, end_date, true)
    schedule = %{
      "Friday" => ["08:00-18:00"],
      "Monday" => ["08:00-18:00"],
      "Saturday" => [],
      "Sunday" => [],
      "Thursday" => ["08:00-18:00"],
      "Tuesday" => ["08:00-18:00"],
      "Wednesday" => ["08:00-18:00"]
    }
    |> Enum.filter(fn {_, v} -> length(v) != 0 end)
    |> Enum.into(%{})

    days =
      schedule
      |> Enum.map(fn(sc) ->
        {day, hours} = sc
        if length(hours) != 0, do: day
      end) |> Enum.filter(& !is_nil(&1))

    valid_dates =
      Enum.filter(all_days, fn(day) ->
        Enum.member?(days, day |> Calendar.Strftime.strftime!("%A"))
      end)


  end

  def ambiguous_handle(value) do
    case value do
      {:ok, datetime} -> datetime
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd
    end
  end
end
