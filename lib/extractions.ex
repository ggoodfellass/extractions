defmodule Extraction do
  @format ~r[(?<start_hour>\d{2}):(?<start_minute>\d{2})-(?<end_hour>\d{2}):(?<end_minute>\d{2})]
  @url_format ~r[/(?<camera_exid>.*)/snapshots/recordings/(?<year>\d{4})/(?<month>\d{1,2})/(?<day>\d{1,2})/(?<hour>\d{1,2})/(?<minute>\d{2})_(?<seconds>\d{2})_(?<milliseconds>\d{3})\.jpg]
  @root_dir Application.get_env(:evercam_media, :storage_dir)

  import Commons
  import EvercamMedia.Snapshot.Storage

  require Logger

  def start(extractor) do
    start_date = extractor.from_date #Calendar.DateTime.from_erl!({{2020, 5, 24},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    end_date = extractor.to_date #Calendar.DateTime.from_erl!({{2020, 5, 24},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    schedule =
      extractor.schedule
      |> Enum.filter(fn {_, v} -> length(v) != 0 end)
      |> Enum.into(%{})

    days =
      schedule
      |> Enum.map(fn(sc) ->
        {day, hours} = sc
        if length(hours) != 0, do: day
      end) |> Enum.filter(& !is_nil(&1))

    camera_exid = extractor.camera_exid
    camera_timezone = extractor.timezone

    interval = extractor.interval

    File.mkdir_p(images_directory = "#{@root_dir}/#{camera_exid}/extract/#{extractor.id}/")

    all_days =
      Calendar.Date.days_after_until(start_date, end_date, true)
      |> Enum.filter(fn(day) ->
        Enum.member?(days, day |> Calendar.Strftime.strftime!("%A"))
      end)

    valid_dates =
      all_days
      |> get_date_pairs(schedule, camera_timezone)

    IO.inspect expected_count = get_expected_count(valid_dates, interval)

    dates_with_intervals =
      valid_dates
      |> Enum.map(&handle_pair(&1, interval))
      |> List.flatten()
      |> Enum.group_by(&Calendar.DateTime.from_erl!({{&1.year, &1.month, &1.day}, {0, 0, 0}}, camera_timezone))
      |> Enum.filter(&drop_not_available_days(&1, camera_exid) != [])
      |> Enum.flat_map(fn {_drop_date, list_of_datetimes} -> list_of_datetimes end)
      |> Enum.group_by(&Calendar.DateTime.from_erl!({{&1.year, &1.month, &1.day}, {&1.hour, 0, 0}}, camera_timezone))
      |> IO.inspect(limit: :infinity)
      |> Enum.map(&create_valid_urls(&1, camera_exid, interval))
      # |> IO.inspect
      # |> process_url(images_directory)
  end

  defp drop_not_available_days({date, _}, camera_exid) do
    filer = point_to_seaweed(Calendar.DateTime.Format.unix(date))
    request_from_seaweedfs("#{filer.url}/#{camera_exid}/snapshots/recordings/#{strft_date(date, "%Y")}/#{strft_date(date, "%m")}/#{strft_date(date, "%d")}/", filer.type, filer.attribute)
  end

  defp create_valid_urls({date, list_of_dates}, camera_exid, interval) do
    IO.inspect date
    IO.inspect list_of_dates
    filer = point_to_seaweed(Calendar.DateTime.Format.unix(date))
    "#{filer.url}/#{camera_exid}/snapshots/recordings/#{strft_date(date, "%Y")}/#{strft_date(date, "%m")}/#{strft_date(date, "%d")}/#{strft_date(date, "%H")}/?limit=3600"
    |> request_from_seaweedfs(filer.type, filer.attribute)
    |> IO.inspect
  end

  defp process_url([], images_directory) do
    with true <- session_file_exists?(images_directory) do
      commit_if_1000(1000, ElixirDropbox.Client.new(System.get_env["DROP_BOX_TOKEN"]), images_directory)
      Logger.info "Its all done."
    else
      _ -> Logger.info "Nofile has been extracted."
    end
  end 
  defp process_url([head|tail], images_directory) do
    download_results(head, images_directory)
    process_url(tail, images_directory)
  end

  defp download(url), do: HTTPoison.get(url, [], [])

  defp download_results(url, images_directory) do
    send self(), {:url, url}
    download(url)
    |> IO.inspect
    |> results(images_directory)
  end

  defp results({:ok, %HTTPoison.Response{body: body, status_code: 200, request_url: url}}, images_directory) do
    %{
      "day" => day,
      "hour" => hour,
      "minute" => minutes,
      "month" => month,
      "seconds" => seconds,
      "year" => year
    } = Regex.named_captures(@url_format, url)
    upload_session(body, images_directory)
    save_current_jpeg_time("#{year}-#{month}-#{day}T#{hour}:#{minutes}:#{seconds}Z", images_directory)
  end
  defp results({:ok, %HTTPoison.Response{body: "", status_code: 404, request_url: url}}, images_directory) do
    download_results(url, images_directory)
  end
  defp results({:error, %HTTPoison.Error{reason: _reason}}, images_directory) do
    url =
      receive do
        {:url, url} -> url
      end
    download_results(url, images_directory)
  end

  defp upload_session(image, images_directory) do
    image_name = DateTime.to_unix(DateTime.utc_now())
    image_with_dir = images_directory <> image_name <> ".jpg"
    File.write(image_with_dir, image, [:binary]) |> File.close

    client = ElixirDropbox.Client.new(System.get_env["DROP_BOX_TOKEN"])
    {:ok, file_size} = get_file_size(image_with_dir)

    try do
      %{"session_id" => session_id} = ElixirDropbox.Files.UploadSession.start(client, true, image_with_dir)
      write_sessional_values(session_id, file_size, image_with_dir, images_directory)
      check_1000_chunk(images_directory) |> length() |> commit_if_1000(client, images_directory)
    rescue
      _ ->
        :timer.sleep(:timer.seconds(3))
        upload_session(image, images_directory)
    end
  end

  defp handle_pair(%{starting: starting, ending: ending}, interval) do
    {:ok, after_seconds, 0, :after} = Calendar.DateTime.diff(ending, starting)
    chunk = ((after_seconds / interval)) |> Float.ceil |> trunc
    Stream.iterate(starting, &(Calendar.DateTime.add!(&1, interval)))
    |> Enum.take(chunk)
  end

  def get_expected_count(dates, interval) do
    Enum.reduce(dates, 0, fn date_pair, count ->
      %{starting: starting, ending: ending} = date_pair
      {:ok, after_seconds, 0, :after} = Calendar.DateTime.diff(ending, starting)
      count + (after_seconds / interval)
    end) |> Float.ceil |> trunc()
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
end
