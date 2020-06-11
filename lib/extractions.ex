defmodule Extraction do
  @format ~r[(?<start_hour>\d{2}):(?<start_minute>\d{2})-(?<end_hour>\d{2}):(?<end_minute>\d{2})]
  @url_format ~r[/(?<camera_exid>.*)/snapshots/recordings/(?<year>\d{4})/(?<month>\d{1,2})/(?<day>\d{1,2})/(?<hour>\d{1,2})/(?<minute>\d{2})_(?<seconds>\d{2})_(?<milliseconds>\d{3})\.jpg]

  require Logger
  import Commons
  @root_dir "/storage"

  def load_storage_servers() do
    [
      %{
        ip: "159.69.136.31",
        port: "8888",
        start_datetime: Calendar.DateTime.from_erl!({{2018, 11, 01}, {0, 0, 0}}, "Etc/UTC"),
        stop_datetime: Calendar.DateTime.from_erl!({{2019, 10, 31}, {23, 59, 59}}, "Etc/UTC"),
        weed_attribute: "FullPath",
        weed_type: "Entries",
        weed_files: "Entries",
        weed_name: "FullPath",
        server_name: "rubbish",
        weed_mode: "R"
      },
      %{
        ip: "188.40.18.217",
        port: "8888",
        start_datetime: Calendar.DateTime.from_erl!({{2019, 11, 01}, {0, 0, 0}}, "Etc/UTC"),
        stop_datetime: Calendar.DateTime.from_erl!({{2020, 10, 31}, {23, 59, 59}}, "Etc/UTC"),
        weed_attribute: "FullPath",
        weed_type: "Entries",
        weed_files: "Entries",
        weed_name: "FullPath",
        server_name: "rubbish 2",
        weed_mode: "RW"
      }
    ]
    |> Enum.map(fn(server) ->
      :ets.insert_new(:storage_servers, {
        server.server_name,
        server.weed_mode,
        get_server_date_unix(server.start_datetime),
        get_server_date_unix(server.stop_datetime), [
        %{
          server_name: server.server_name,
          url: "http://#{server.ip}:#{server.port}",
          attribute: server.weed_attribute,
          type: server.weed_type,
          files: server.weed_files,
          name: server.weed_name,
          mode: server.weed_mode
        }]}
      )
    end)
  end
  def load_storage_servers(_), do: :noop

  defp get_server_date_unix(nil), do: nil
  defp get_server_date_unix(datetime), do: Calendar.DateTime.Format.unix(datetime)

  def start_extractor() do
    start_date = Calendar.DateTime.from_erl!({{2019, 8, 11},{0, 0, 0}}, "Etc/UTC", {123456, 6})
    end_date = Calendar.DateTime.from_erl!({{2020, 2, 29},{0, 29, 10}}, "Etc/UTC", {123456, 6})
    schedule =
      %{
        "Monday" => ["00:00-23:59"],
        "Tuesday" => ["00:00-23:59"],
        "Wednesday" => ["00:00-23:59"],
        "Thursday" => ["00:00-23:59"],
        "Friday" => ["00:00-23:59"],
        "Saturday" => ["00:00-23:59"],
        "Sunday" => ["00:00-23:59"]
      }
      |> Enum.filter(fn {_, v} -> length(v) != 0 end)
      |> Enum.into(%{})

    days =
      schedule
      |> Enum.map(fn(sc) ->
        {day, hours} = sc
        if length(hours) != 0, do: day
      end) |> Enum.filter(& !is_nil(&1))

    camera_exid = "hornb-vtamg"
    camera_timezone = "Europe/Dublin"

    interval = 1

    File.mkdir_p(images_directory = "#{@root_dir}/#{camera_exid}/")

    all_days =
      Calendar.Date.days_after_until(start_date, end_date, true)
      |> Enum.filter(fn(day) ->
        Enum.member?(days, day |> Calendar.Strftime.strftime!("%A"))
      end)

    valid_dates =
      all_days
      |> get_date_pairs(schedule, camera_timezone)

    inline_process = fn (head, images_directory, camera_timezone) ->
      put_in_stream(head, images_directory, camera_timezone)
    end

    valid_dates
    |> Enum.map(&handle_pair(&1, interval))
    |> List.flatten()
    |> Enum.group_by(&Calendar.DateTime.from_erl!({{&1.year, &1.month, &1.day}, {0, 0, 0}}, "Etc/UTC"))
    |> Enum.filter(&drop_not_available_days(&1, camera_exid) != [])
    |> Enum.flat_map(fn {_drop_date, list_of_datetimes} -> list_of_datetimes end)
    |> Enum.group_by(&Calendar.DateTime.from_erl!({{&1.year, &1.month, &1.day}, {&1.hour, 0, 0}}, "Etc/UTC"))
    |> Enum.map(&create_valid_urls(&1, camera_exid))
    |> List.flatten()
    |> Enum.sort()
    |> to_ignore(images_directory)
    |> IO.inspect
    |> Task.async_stream(&(inline_process.(&1, images_directory, camera_timezone)), max_concurrency: System.schedulers_online() * 2, timeout: :infinity)
    |> Stream.run
  end

  defp to_ignore(list, images_directory) do
    try do
      rejections =
        File.read!("#{images_directory}CURRENT")
        |> String.split("\n", trim: true)
        |> Enum.sort()
      Enum.reject(list, fn(url) -> url in rejections end)
    rescue
      _ ->
        list
    end
  end

  defp drop_not_available_days({date, _}, camera_exid) do
    filer = point_to_seaweed(Calendar.DateTime.Format.unix(date))
    request_from_seaweedfs("#{filer.url}/#{camera_exid}/snapshots/recordings/#{strft_date(date, "%Y")}/#{strft_date(date, "%m")}/#{strft_date(date, "%d")}/", filer.type, filer.attribute)
  end

  defp create_valid_urls({date, _list_of_dates}, camera_exid) do
    filer = point_to_seaweed(Calendar.DateTime.Format.unix(date))
    "#{filer.url}/#{camera_exid}/snapshots/recordings/#{strft_date(date, "%Y")}/#{strft_date(date, "%m")}/#{strft_date(date, "%d")}/#{strft_date(date, "%H")}/?limit=3600"
    |> request_from_seaweedfs(filer.type, filer.attribute)
    |> Enum.map(&"#{filer.url}/#{camera_exid}/snapshots/recordings/#{strft_date(date, "%Y")}/#{strft_date(date, "%m")}/#{strft_date(date, "%d")}/#{strft_date(date, "%H")}/#{&1}")
  end

  defp put_in_stream(head, images_directory, camera_timezone) do
    download(head)
    |> results(images_directory, camera_timezone)
  end

  defp download(url), do: HTTPoison.get(url, [], hackney: [pool: :seaweedfs_download_pool, recv_timeout: 15_000])

  defp results({:ok, %HTTPoison.Response{body: body, status_code: 200, request_url: url}}, images_directory, camera_timezone) do
    %{
      "day" => day,
      "hour" => hour,
      "minute" => minutes,
      "month" => month,
      "seconds" => seconds,
      "year" => year
    } = Regex.named_captures(@url_format, url)
    {:ok, datetime} = "#{year}-#{month}-#{day}T#{hour}:#{minutes}:#{seconds}Z" |> Calendar.DateTime.Parse.rfc3339(camera_timezone)
    save_current_jpeg_time(url, images_directory, :v2)
    upload_session(body, images_directory, Calendar.DateTime.Format.unix(datetime))
  end
  defp results({:ok, %HTTPoison.Response{body: "", status_code: 404, request_url: _url}}, _images_directory, _camera_timezone), do: :noop
  defp results({:error, %HTTPoison.Error{reason: _reason}}, _images_directory, _camera_timezone), do: :noop

  defp upload_session(image, images_directory, image_name) do
    image_with_dir = images_directory <> "#{image_name}" <> ".jpg"
    File.write(image_with_dir, image, [:binary]) |> File.close
  end

  defp handle_pair(%{starting: starting, ending: ending}, interval) do
    {:ok, after_seconds, 0, :after} = Calendar.DateTime.diff(ending, starting)
    chunk = ((after_seconds / interval)) |> Float.ceil |> trunc
    Stream.iterate(starting, &(Calendar.DateTime.add!(&1, interval)))
    |> Enum.take(chunk)
  end

  defp get_date_pairs(dates, schedule, timezone) do
    dates
    |> Enum.map(fn date ->
      schedule[Calendar.Strftime.strftime!(date, "%A")]
      |> get_head_tail
      |> Enum.map(fn timings -> Regex.named_captures(@format, timings |> List.first) end)
      |> Enum.map(fn schedule_time ->
        Map.merge(
          %{
            "year" => strft_date(date, "%Y"),
            "month" => strft_date(date, "%m"),
            "day" => strft_date(date, "%d")
          },
          schedule_time
        )
      end)
    end)
    |> List.flatten
    |> Enum.map(fn date_tuple ->
      {starting, ending} = parse_schedule_times(date_tuple)
      %{
        starting: Calendar.DateTime.from_erl!(starting, timezone, {123456, 6}) |> shift_zone_to_saved_one,
        ending: Calendar.DateTime.from_erl!(ending, timezone, {123456, 6}) |> shift_zone_to_saved_one
      }
    end)
  end

  defp strft_date(date, pattern), do: Calendar.Strftime.strftime!(date, pattern)

  defp shift_zone_to_saved_one(date), do: date |> Calendar.DateTime.shift_zone!("Etc/UTC")

  defp parse_schedule_times(%{"end_hour" => end_hour, "end_minute" => end_minute, "start_hour" => start_hour, "start_minute" => start_minute, "year" => year, "month" => month, "day" => day}) do
    {{{String.to_integer(year), String.to_integer(month), String.to_integer(day)}, {String.to_integer(start_hour), String.to_integer(start_minute), 0}}, {{String.to_integer(year), String.to_integer(month), String.to_integer(day)}, {String.to_integer(end_hour), String.to_integer(end_minute), 0}}}
  end

  defp request_from_seaweedfs(url, type, attribute) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15_000]
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Jason.decode(body),
         true <- is_list(data[type]) do
      Enum.map(data[type], fn(item) -> item[attribute] |> get_base_name(type, attribute) end)
    else
      _ -> []
    end
  end

  defp get_base_name(list, "Entries", "FullPath"), do: list |> Path.basename
  defp get_base_name(list, _, _), do: list

  def point_to_seaweed(request_date) do
    :ets.select(:storage_servers,
      [{
        {:_, :_, :"$1", :"$2", :"$3"},
        [{:andalso, {:>, {:const, request_date}, :"$1"}, {:<, {:const, request_date}, :"$2"}}],
        [:"$3"]
      }])
    |> found_server
  end

  defp found_server([]) do
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    server
  end
  defp found_server([[server]]), do: server
end