# Quickbase

Elixir client for the [Quickbase JSON RESTful API](https://developer.quickbase.com/), built on [Req](https://hexdocs.pm/req).

- Query records, run saved reports, upsert and delete records, list fields and tables
- `stream_records/2` lazily pages through large result sets
- Transient failures on read calls retried automatically (Req built-in retry)
- Helpers for Quickbase's field-id-keyed row format (`value/2`, `by_label/3`)
- Easy to test: pass any Req option through `new/1`, including `plug: {Req.Test, ...}`

## Installation

```elixir
def deps do
  [
    {:quickbase, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
client = Quickbase.new(realm: "demo.quickbase.com", token: System.fetch_env!("QB_USER_TOKEN"))

# Query records
{:ok, %{"data" => rows, "fields" => fields}} =
  Quickbase.query_records(client,
    from: "bck7gp3q2",
    select: [3, 6, 7],
    where: "{'6'.EX.'Done'}",
    sort_by: [%{"fieldId" => 6, "order" => "ASC"}]
  )

# Unwrap values by field id or label
idx = Quickbase.label_index(fields)

for row <- rows do
  {Quickbase.value(row, 3), Quickbase.by_label(row, idx, "Status")}
end

# Stream every record, paging automatically
client
|> Quickbase.stream_records(from: "bck7gp3q2", select: [3])
|> Enum.count()

# Run a saved report
{:ok, report} = Quickbase.run_report(client, 7, "bck7gp3q2")

# Insert/update records
Quickbase.upsert_records(client, "bck7gp3q2", [
  %{"6" => %{"value" => "New task"}}
])

# Delete records
Quickbase.delete_records(client, "bck7gp3q2", "{'3'.EX.'42'}")
```

Every function has a bang variant (`query_records!/2`, ...) that returns the
body directly and raises `Quickbase.Error` (API error) or a transport
exception on failure.

## Testing your app

`new/1` forwards unknown options to `Req.new/1`, so stub responses with
[`Req.Test`](https://hexdocs.pm/req/Req.Test.html):

```elixir
client = Quickbase.new(realm: "r", token: "t", plug: {Req.Test, MyStub})

Req.Test.stub(MyStub, fn conn ->
  Req.Test.json(conn, %{"data" => []})
end)
```

## Debugging

`new/1` returns a plain `Req.Request`, so attach logging steps with
[`Req.Request`](https://hexdocs.pm/req/Req.Request.html) to see every
request and response:

```elixir
client =
  Quickbase.new(realm: "r", token: "t")
  |> Req.Request.append_request_steps(
    log_request: fn req ->
      Logger.debug("quickbase: #{req.method} #{req.url}")
      req
    end
  )
  |> Req.Request.append_response_steps(
    log_response: fn {req, resp} ->
      Logger.debug("quickbase: #{resp.status}")
      {req, resp}
    end
  )
```

## License

MIT
