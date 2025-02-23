#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(2);
no_long_string();
no_root_location();
run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 'test-key'}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
done



=== TEST 2: wrong type of string
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local plugin = require("apisix.plugins.key-auth")
            local ok, err = plugin.check_schema({key = 123}, core.schema.TYPE_CONSUMER)
            if not ok then
                ngx.say(err)
            end

            ngx.say("done")
        }
    }
--- request
GET /t
--- response_body
property "key" validation failed: wrong type: expected string, got number
done



=== TEST 3: add consumer with username and plugins
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "auth-one"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 4: add key auth plugin using admin api
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {}
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 5: valid consumer
--- request
GET /hello
--- more_headers
apikey: auth-one
--- response_body
hello world



=== TEST 6: invalid consumer
--- request
GET /hello
--- more_headers
apikey: 123
--- error_code: 401
--- response_body
{"message":"Invalid API key in request"}



=== TEST 7: not found apikey header
--- request
GET /hello
--- error_code: 401
--- response_body
{"message":"Missing API key found in request"}



=== TEST 8: valid consumer
--- config
    location /add_more_consumer {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local username = ""
            local key = ""
            local code, body
            for i = 1, 20 do
                username = "user_" .. tostring(i)
                key = "auth-" .. tostring(i)
                code, body = t('/apisix/admin/consumers',
                    ngx.HTTP_PUT,
                    string.format('{"username":"%s","plugins":{"key-auth":{"key":"%s"}}}', username, key),
                    string.format('{"value":{"username":"%s","plugins":{"key-auth":{"key":"%s"}}}}', username, key)
                    )
            end

            ngx.status = code
            ngx.say(body)
        }
    }
--- request
GET /add_more_consumer
--- pipelined_requests eval
["GET /add_more_consumer", "GET /hello"]
--- more_headers
apikey: auth-13
--- response_body eval
["passed\n", "hello world\n"]



=== TEST 9: add consumer with empty key
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "error",
                    "plugins": {
                        "key-auth": {
                        }
                    }
                }]]
                )

            ngx.status = code
            ngx.print(body)
        }
    }
--- request
GET /t
--- error_code: 400
--- response_body
{"error_msg":"invalid plugins configuration: failed to check the configuration of plugin key-auth err: property \"key\" is required"}



=== TEST 10: customize header
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "header": "Authorization"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 11: valid consumer
--- request
GET /hello
--- more_headers
Authorization: auth-one
--- response_body
hello world



=== TEST 12: customize query string
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "query": "auth"
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 13: valid consumer
--- request
GET /hello?auth=auth-one
--- response_body
hello world



=== TEST 14: enable key auth plugin using admin api, set hide_credentials = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "hide_credentials": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 15: verify apikey request header should not hidden
--- request
GET /echo
--- more_headers
apikey: auth-one
--- response_headers
apikey: auth-one



=== TEST 16: add key auth plugin using admin api, set hide_credentials = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "hide_credentials": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 17: verify apikey request header is hidden
--- request
GET /echo
--- more_headers
apikey: auth-one
--- response_headers
!apikey



=== TEST 18: verify that only the keys in the title are deleted
--- request
GET /echo
--- more_headers
apikey: auth-one
test: auth-two
--- response_headers
!apikey
test: auth-two



=== TEST 19: when apikey both in header and query string, verify apikey request header is hidden but request args is not hidden
--- request
GET /echo?apikey=auth-one
--- more_headers
apikey: auth-one
--- response_headers
!apikey
--- response_args
apikey: auth-one



=== TEST 20: customize query string, set hide_credentials = true
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "query": "auth",
                            "hide_credentials": true
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/echo"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 21: verify auth request args is hidden
--- request
GET /echo?auth=auth-one
--- response_args
!auth



=== TEST 22: verify that only the keys in the query parameters are deleted
--- request
GET /echo?auth=auth-one&test=auth-two
--- response_args
!auth
test: auth-two



=== TEST 23: when auth both in header and query string, verify auth request args is hidden but request header is not hidden
--- request
GET /echo?auth=auth-one
--- more_headers
auth: auth-one
--- response_headers
auth: auth-one
--- response_args
!auth



=== TEST 24: customize query string, set hide_credentials = false
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/routes/1',
                ngx.HTTP_PUT,
                [[{
                    "plugins": {
                        "key-auth": {
                            "query": "auth",
                            "hide_credentials": false
                        }
                    },
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 25: verify auth request args should not hidden
--- request
GET /hello?auth=auth-one
--- response_args
auth: auth-one



=== TEST 26: change consumer with secrets ref
--- config
    location /t {
        content_by_lua_block {
            local t = require("lib.test_admin").test
            local code, body = t('/apisix/admin/consumers',
                ngx.HTTP_PUT,
                [[{
                    "username": "jack",
                    "plugins": {
                        "key-auth": {
                            "key": "$env://test_auth"
                        }
                    }
                }]]
                )

            if code >= 300 then
                ngx.status = code
            end
            ngx.say(body)
        }
    }
--- request
GET /t
--- response_body
passed



=== TEST 27: verify auth request args should not hidden
--- main_config
env test_auth=authone;
--- request
GET /hello?auth=authone
--- response_args
auth: authone
