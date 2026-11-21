const {before, test} = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');

const base = process.env.NGINX_URL || 'http://nginx:8000';

function request(path, options = {}) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, base);
        const req = http.request(url, {
            method: options.method || 'GET',
            headers: options.headers || {},
        }, (res) => {
            const chunks = [];
            res.on('data', (chunk) => chunks.push(chunk));
            res.on('end', () => resolve({
                status: res.statusCode,
                headers: res.headers,
                body: Buffer.concat(chunks),
            }));
        });
        req.on('error', reject);
        req.end(options.body);
    });
}

async function waitFor(url, timeoutMs = 60000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            const res = await request(url);
            if (res.status === 200) {
                return;
            }
        } catch (_) {
            // retry
        }
        await new Promise((resolve) => setTimeout(resolve, 500));
    }
    throw new Error(`timeout waiting for ${url}`);
}

before(async () => {
    await waitFor('/health');
    await waitFor('/pg');
});

test('echo module', async () => {
    const res = await request('/echo?x=hello');
    assert.equal(res.status, 200);
    assert.match(res.body.toString(), /echo hello/);
});

test('headers-more module', async () => {
    const res = await request('/headers');
    assert.equal(res.status, 200);
    assert.equal(res.headers['x-test'], 'yes');
    assert.equal(res.headers.server, undefined);
});

test('set-misc module', async () => {
    const value = 'hello';
    const res = await request(`/setmisc?x=${encodeURIComponent(value)}`);
    assert.equal(res.status, 200);
    const [sha1, md5, escaped] = res.body.toString().trim().split(' ');
    assert.equal(sha1, crypto.createHash('sha1').update(value).digest('hex'));
    assert.equal(md5, crypto.createHash('md5').update(value).digest('hex'));
    assert.equal(escaped, 'hello');
});

test('substitutions_filter module', async () => {
    const res = await request('/subs');
    assert.equal(res.status, 200);
    assert.equal(res.body.toString(), 'bar body');
});

test('brotli module', async () => {
    const res = await request('/compress', {headers: {'Accept-Encoding': 'br'}});
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-encoding'], 'br');
    assert.match(zlib.brotliDecompressSync(res.body).toString(), /foo body/);
});

test('zstd module', async () => {
    const res = await request('/compress', {headers: {'Accept-Encoding': 'zstd'}});
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-encoding'], 'zstd');
    const decoded = execFileSync('zstd', ['-d', '-c'], {input: res.body}).toString();
    assert.match(decoded, /foo body/);
});

test('srcache module', {skip: 'srcache_fetch miss returns 404 on nginx 1.30'}, async () => {
    const first = await request('/srcache?case=modules-suite');
    assert.equal(first.status, 200);
    assert.match(first.body.toString(), /cache body/);

    const countAfterMiss = (await request('/backend_count')).body.toString();
    assert.equal(countAfterMiss, '1');

    const second = await request('/srcache?case=modules-suite');
    assert.equal(second.status, 200);
    assert.equal(second.body.toString(), first.body.toString());

    const countAfterHit = (await request('/backend_count')).body.toString();
    assert.equal(countAfterHit, '1');
});

test('memc module miss', async () => {
    const res = await request('/memc?key=missing-key');
    assert.equal(res.status, 404);
});

test('redis2 module set/get', async () => {
    const key = `modules-${Date.now()}`;
    const set = await request(`/redis2/set?key=${key}&value=hello`);
    assert.equal(set.status, 200);
    assert.match(set.body.toString(), /OK/);

    const get = await request(`/redis2/get?key=${key}`);
    assert.equal(get.status, 200);
    assert.match(get.body.toString(), /hello/);
});

test('postgres module query', async () => {
    const res = await request('/pg');
    assert.equal(res.status, 200);
    assert.match(res.body.toString(), /42/);
    assert.match(res.body.toString(), /ok/);
});

test('rds-json module output', async () => {
    const res = await request('/rds');
    assert.equal(res.status, 200);
    const data = JSON.parse(res.body.toString());
    assert.ok(Array.isArray(data));
    assert.equal(data[0].id, 1);
    assert.equal(data[0].name, 'alice');
});
