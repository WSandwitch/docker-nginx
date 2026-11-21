const http = require('node:http');

const prefix = '/v1/kv/upstreams/test/';
const keys = new Map();
let index = 1;

function add(key, value = '{"weight":1,"max_fails":2,"fail_timeout":10}') {
    keys.set(key, Buffer.from(value).toString('base64'));
    index += 1;
}

add('upstreams/test/172.23.0.11:9000');

const server = http.createServer((req, res) => {
    if (req.method === 'PUT' && req.url.startsWith(prefix)) {
        const key = decodeURIComponent(req.url.slice(1).split('?')[0]);
        let body = '';
        req.on('data', (chunk) => { body += chunk; });
        req.on('end', () => {
            add(key, body || '{"weight":1,"max_fails":2,"fail_timeout":10}');
            res.writeHead(200, {'Content-Type': 'text/plain'});
            res.end('true');
        });
        return;
    }

    if (req.method === 'GET' && req.url.startsWith(prefix)) {
        const data = [...keys.entries()].map(([Key, Value]) => ({
            Key,
            Value,
            CreateIndex: 1,
            ModifyIndex: index,
            LockIndex: 0,
            Flags: 0,
        }));
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'X-Consul-Index': String(index),
        });
        res.end(JSON.stringify(data));
        return;
    }

    res.writeHead(404, {'Content-Type': 'text/plain'});
    res.end('not found');
});

server.listen(8500, '0.0.0.0');
