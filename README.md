# NotifyBridge

A small macOS menu bar app that listens on an HTTP endpoint and shows each message it receives in Notification Center.

## Build and run

```sh
./build.sh
open build/NotifyBridge.app
```

Requires the Xcode command line tools (Swift 5.9+) and macOS 13 or later. On first launch macOS asks whether NotifyBridge may send notifications; choose **Allow**. A bell icon appears in the menu bar showing the listening address.

To keep it around, copy `build/NotifyBridge.app` to `/Applications` and add it under System Settings > General > Login Items.

## Sending a notification

`POST /notify` with a JSON body:

```sh
curl -X POST http://127.0.0.1:8787/notify \
  -H 'Content-Type: application/json' \
  -d '{"title": "Build finished", "subtitle": "main", "message": "All tests passed"}'
```

| Field      | Required | Notes                              |
|------------|----------|------------------------------------|
| `message`  | yes      | Notification text (`body` also works) |
| `title`    | no       | Defaults to `NotifyBridge`         |
| `subtitle` | no       |                                    |
| `sound`    | no       | `false` for a silent notification  |

Or send plain text, with the title in the query string:

```sh
curl -X POST 'http://127.0.0.1:8787/notify?title=Backup' -d 'Nightly backup complete'
```

Responses are JSON: `{"status":"ok"}` with 200, or `{"status":"error","error":"..."}` with 400 (bad request), 401 (bad token), or 503 (notifications are disabled for the app).

`GET /health` returns `{"status":"ok"}`.

## Settings

Settings are read at launch from the app's defaults. Quit and reopen after changing them.

| Key     | Default     | Purpose                                                 |
|---------|-------------|---------------------------------------------------------|
| `port`  | `8787`      | Listening port                                          |
| `host`  | `127.0.0.1` | Bind address. Use `0.0.0.0` to accept other machines    |
| `token` | none        | If set, requests need `Authorization: Bearer <token>`   |

```sh
defaults write com.local.notifybridge port -int 9000
defaults write com.local.notifybridge token "some-secret"
```

For a single launch: `open build/NotifyBridge.app --args -port 9000`.

By default only programs on this Mac can reach the endpoint. If you set `host` to `0.0.0.0`, set a `token` too; the connection is plain HTTP, so only do this on a network you trust.
