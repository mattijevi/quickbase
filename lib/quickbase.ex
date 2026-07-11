defmodule Quickbase do
  @moduledoc """
  Client for the [Quickbase JSON RESTful API](https://developer.quickbase.com/).

  Build a client with `new/1`, then pass it to the API functions:

      client = Quickbase.new(realm: "demo.quickbase.com", token: System.fetch_env!("QB_USER_TOKEN"))

      {:ok, %{"data" => rows}} =
        Quickbase.query_records(client,
          from: "bck7gp3q2",
          select: [3, 6, 7],
          where: "{'6'.EX.'Done'}"
        )

  All functions return `{:ok, body}` on HTTP 200 or `{:error, reason}`,
  where `reason` is a `Quickbase.Error` (non-200 response) or an exception
  (transport error). Bang variants (`query_records!/2`, etc.) return the
  body directly and raise on failure.

  ## Working with rows

  Quickbase returns records keyed by stringified field id
  (`%{"6" => %{"value" => "Done"}}`). See `value/2`, `label_index/1`, and
  `by_label/3` for helpers that unwrap them.

  ## Options

  `new/1` accepts:

    * `:realm` (required) — your realm hostname, e.g. `"demo.quickbase.com"`
    * `:token` (required) — a Quickbase user token
    * `:user_agent` — optional `User-Agent` header value
    * any other option is forwarded to `Req.new/1` (`:plug`, `:finch`,
      `:receive_timeout`, ...), so the client is easy to test with `Req.Test`
      and tune for production pools.

  Read-only calls (`query_records/2`, `run_report/3`, `list_fields/2`,
  `list_tables/2`) are retried on transient failures via Req's built-in
  retry; mutations (`upsert_records/3`, `delete_records/3`) are not.
  """

  @type client :: Req.Request.t()
  @type response :: {:ok, map() | list()} | {:error, Quickbase.Error.t() | Exception.t()}

  @base_url "https://api.quickbase.com/v1"

  @doc """
  Builds a client for the given realm and user token.

  Returns a `Req.Request` that the other functions in this module accept.
  """
  @spec new(keyword()) :: client()
  def new(opts) do
    {realm, opts} = Keyword.pop!(opts, :realm)
    {token, opts} = Keyword.pop!(opts, :token)
    {user_agent, opts} = Keyword.pop(opts, :user_agent)

    headers =
      %{"qb-realm-hostname" => realm, "authorization" => "QB-USER-TOKEN #{token}"}
      |> then(&if user_agent, do: Map.put(&1, "user-agent", user_agent), else: &1)

    Req.new([base_url: @base_url, headers: headers, retry: false] ++ opts)
  end

  @doc """
  Queries records in a table (`POST /records/query`).

  ## Options

    * `:from` (required) — table id
    * `:select` — list of field ids to return
    * `:where` — a [Quickbase query string](https://developer.quickbase.com/pages/components-queries)
    * `:sort_by` — list of maps, e.g. `[%{"fieldId" => 6, "order" => "ASC"}]`
    * `:group_by` — list of maps, e.g. `[%{"fieldId" => 6, "grouping" => "equal-values"}]`
    * `:skip` / `:top` — pagination offset and page size

  See `stream_records/2` to page through large result sets lazily.
  """
  @spec query_records(client(), keyword()) :: response()
  def query_records(client, opts) do
    client
    |> Req.post(url: "/records/query", json: query_body(opts), retry: :transient)
    |> handle()
  end

  @doc "Same as `query_records/2` but returns the body and raises on failure."
  @spec query_records!(client(), keyword()) :: map()
  def query_records!(client, opts), do: bang(query_records(client, opts))

  @doc """
  Lazily streams all records matching a query, paging through
  `POST /records/query` under the hood.

  Takes the same options as `query_records/2`; `:top` controls the page
  size (default 500) and `:skip` the starting offset. Emits individual
  row maps. Raises on request failure mid-stream.

      client |> Quickbase.stream_records(from: "bck7gp3q2", select: [3]) |> Enum.count()
  """
  @spec stream_records(client(), keyword()) :: Enumerable.t()
  def stream_records(client, opts) do
    top = Keyword.get(opts, :top, 500)
    skip = Keyword.get(opts, :skip, 0)

    Stream.resource(
      fn -> skip end,
      fn
        :done ->
          {:halt, :done}

        offset ->
          body = query_records!(client, Keyword.merge(opts, skip: offset, top: top))
          rows = body["data"] || []
          %{"numRecords" => num, "totalRecords" => total} = body["metadata"]

          if rows == [] or offset + num >= total do
            {rows, :done}
          else
            {rows, offset + num}
          end
      end,
      fn _acc -> :ok end
    )
  end

  @doc """
  Runs a saved report (`POST /reports/{id}/run`).

      Quickbase.run_report(client, 7, "bck7gp3q2")
  """
  @spec run_report(client(), integer() | String.t(), String.t()) :: response()
  def run_report(client, report_id, table_id) do
    client
    |> Req.post(url: "/reports/#{report_id}/run", params: [tableId: table_id], retry: :transient)
    |> handle()
  end

  @doc "Same as `run_report/3` but returns the body and raises on failure."
  @spec run_report!(client(), integer() | String.t(), String.t()) :: map()
  def run_report!(client, report_id, table_id), do: bang(run_report(client, report_id, table_id))

  @doc """
  Inserts or updates records (`POST /records`).

  `records` is a list of row maps keyed by field id:

      Quickbase.upsert_records(client, "bck7gp3q2", [
        %{"6" => %{"value" => "Task name"}, "7" => %{"value" => 12}}
      ])

  Pass `merge_field_id:` to update existing records matching on that field,
  and `fields_to_return:` to get field values back in the response.
  """
  @spec upsert_records(client(), String.t(), [map()], keyword()) :: response()
  def upsert_records(client, table_id, records, opts \\ []) do
    body =
      %{"to" => table_id, "data" => records}
      |> put_if(opts, :merge_field_id, "mergeFieldId")
      |> put_if(opts, :fields_to_return, "fieldsToReturn")

    client |> Req.post(url: "/records", json: body) |> handle()
  end

  @doc "Same as `upsert_records/4` but returns the body and raises on failure."
  @spec upsert_records!(client(), String.t(), [map()], keyword()) :: map()
  def upsert_records!(client, table_id, records, opts \\ []),
    do: bang(upsert_records(client, table_id, records, opts))

  @doc """
  Deletes records matching a query (`DELETE /records`).

      Quickbase.delete_records(client, "bck7gp3q2", "{'3'.EX.'42'}")
  """
  @spec delete_records(client(), String.t(), String.t()) :: response()
  def delete_records(client, table_id, where) do
    client
    |> Req.delete(url: "/records", json: %{"from" => table_id, "where" => where})
    |> handle()
  end

  @doc "Same as `delete_records/3` but returns the body and raises on failure."
  @spec delete_records!(client(), String.t(), String.t()) :: map()
  def delete_records!(client, table_id, where), do: bang(delete_records(client, table_id, where))

  @doc "Lists the fields of a table (`GET /fields`)."
  @spec list_fields(client(), String.t()) :: response()
  def list_fields(client, table_id) do
    client
    |> Req.get(url: "/fields", params: [tableId: table_id], retry: :transient)
    |> handle()
  end

  @doc "Same as `list_fields/2` but returns the body and raises on failure."
  @spec list_fields!(client(), String.t()) :: list()
  def list_fields!(client, table_id), do: bang(list_fields(client, table_id))

  @doc "Lists the tables of an app (`GET /tables`)."
  @spec list_tables(client(), String.t()) :: response()
  def list_tables(client, app_id) do
    client
    |> Req.get(url: "/tables", params: [appId: app_id], retry: :transient)
    |> handle()
  end

  @doc "Same as `list_tables/2` but returns the body and raises on failure."
  @spec list_tables!(client(), String.t()) :: list()
  def list_tables!(client, app_id), do: bang(list_tables(client, app_id))

  ## Row helpers

  @doc """
  Unwraps the value of a field in a row returned by `query_records/2` or
  `run_report/3`. Accepts the field id as integer or string.

      iex> Quickbase.value(%{"6" => %{"value" => "Done"}}, 6)
      "Done"
  """
  @spec value(map(), integer() | String.t()) :: term()
  def value(row, fid), do: get_in(row, [to_string(fid), "value"])

  @doc """
  Builds a `%{label => field id string}` map from the `"fields"` list of a
  response, for use with `by_label/3`.

      iex> Quickbase.label_index([%{"id" => 6, "label" => "Status"}])
      %{"Status" => "6"}
  """
  @spec label_index([map()]) :: %{optional(String.t()) => String.t()}
  def label_index(fields) do
    Map.new(fields, fn %{"id" => id, "label" => label} -> {label, to_string(id)} end)
  end

  @doc """
  Unwraps the value of a field in a row by its label, using an index built
  with `label_index/1`. Returns `nil` when the label is unknown.

      iex> idx = Quickbase.label_index([%{"id" => 6, "label" => "Status"}])
      iex> Quickbase.by_label(%{"6" => %{"value" => "Done"}}, idx, "Status")
      "Done"
  """
  @spec by_label(map(), map(), String.t()) :: term()
  def by_label(row, index, label) do
    case Map.get(index, label) do
      nil -> nil
      fid -> value(row, fid)
    end
  end

  ## Internals

  defp query_body(opts) do
    options =
      %{}
      |> put_if(opts, :skip, "skip")
      |> put_if(opts, :top, "top")

    %{
      "from" => Keyword.fetch!(opts, :from),
      "select" => Keyword.get(opts, :select, []),
      "where" => Keyword.get(opts, :where, ""),
      "sortBy" => Keyword.get(opts, :sort_by, []),
      "groupBy" => Keyword.get(opts, :group_by, [])
    }
    |> then(&if options == %{}, do: &1, else: Map.put(&1, "options", options))
  end

  defp put_if(map, opts, key, api_key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> Map.put(map, api_key, value)
      :error -> map
    end
  end

  defp handle({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}

  defp handle({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, %Quickbase.Error{status: status, body: body}}

  defp handle({:error, exception}), do: {:error, exception}

  defp bang({:ok, body}), do: body
  defp bang({:error, %{__exception__: true} = error}), do: raise(error)
end
