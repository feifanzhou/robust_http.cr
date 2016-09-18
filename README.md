# robust_http

Wrapper around HTTP::Client that automatically handles retries with exponential backoff. Developed and tested with Crystal 0.19.2 on OS X 10.11.4

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  robust_http:
    github: feifanzhou/robust_http.cr
```

## Usage


```crystal
require "robust_http"
```

`RobustHTTP.exec(host : String, port, request : HTTP::Request, timeout : Float)`

## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/feifanzhou/robust_http.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [feifanzhou](https://github.com/feifanzhou) Feifan Zhou - creator, maintainer
