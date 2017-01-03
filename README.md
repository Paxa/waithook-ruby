# Waithook ruby client

A ruby client [Waithook](https://waithook.herokuapp.com).
Wiathook is a service to transmit HTTP requests over websocket connection.
It's kinda Pub/Sub system for HTTP notifications, built for recieving webhook notifications behind proxy or when public IP is unknown (such as cloud CI server).


To recieve notifications you should add `https://waithook.herokuapp.com/some_random_string` as notification URL and start listening websocket messages at `wss://waithook.herokuapp.com/some_random_string`.

### Command line usage

Install:
```sh
gem install waithook
```

Subscribe and print incoming requests:
````sh
waithook waithook.herokuapp.com/my_path
```

Subscribe and forvard to other web server:
````sh
waithook waithook.herokuapp.com/my_path --forward http://localhost:3000/notify
```

### Ruby API

```ruby
waithook = Waithook.subscribe(timeout: 60, raise_on_timeout: true) do |webhook|
  webhook.json_body['order_id'] == order_id
end

waithook.send_to("http://localhost:3000/notify")
```

### Usage examples

* Testing integration with payment gateway
* Testing github webhooks
* Testing incoming email processing
* Testing slack bots
* Testing facebook webhooks

So waithook just help to deliver webhook to your application when public IP is unknown or not available. It can help when multiple developers testing integration with other service on localhost or your automated tests running in CI.

