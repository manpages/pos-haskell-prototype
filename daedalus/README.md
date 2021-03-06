# `daedalus-bridge`

API for Daedalus.


## Build `daedalus-bridge` locally

To try `daedalus-bridge` locally you have to run `wallet-api`, first. Note that your are on root folder of `pos-haskell-prototype`.

```bash
# build app
stack build --flag cardano-sl:with-wallet --flag cardano-sl:with-web
# run tmux in another window
tmux
# generate PureScript types
stack exec -- cardano-wallet-hs2purs
# launch nodes
export WALLET_TEST=1; ./scripts/launch.sh
```

Run `daedalus-bridge` locally:

```bash
cd daedalus
npm install
npm start
open http://localhost:3080/
```

After that you can try examples described in chapter ["Usage"](#Usage) using console of your browser.


## Build `daedalus-bridge` for production

```bash
npm run build:prod
```

`daedalus-bridge` is build to `dist/Daedalus.js`.

Note: `daedalus-bridge` is not optimized / compressed. This is will be a job for Daedalus.


## Usage (ES5)

API of `daedalus-bridge` does provide following Promise based functions:

_getWallets_

```javascript
Daedalus.ClientApi.getWallets()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log('ERROR', reason);
  })
```


_getWallet_

```javascript
// XXX - any wallet id
Daedalus.ClientApi.getWallet('XXX')()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log('ERROR', reason);
  })
```


_newWallet_

```javascript
Daedalus.ClientApi.newWallet('CWTPersonal', 'ADA', '')()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log('ERROR', reason);
  })
```


_deleteWallet_

```javascript
// XXX - any wallet id
Daedalus.ClientApi.deleteWallet('XXX')()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log(reason);
  })
```


_send_

```javascript
// IdFrom - wallet id to send amount from
// IdTo - wallet id to send amount to
Daedalus.ClientApi.send('IdFrom', 'IdTo', 80)()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log(reason);
  })
```


_history_

```javascript
// XXX - wallet id
Daedalus.ClientApi.getHistory('XXX')()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log(reason);
  })
```


_isValidAddress_

```javascript
// XXX - wallet id
Daedalus.ClientApi.isValidAddress('XXX', 'ADA')()
  .then(function(value) {
    console.log('SUCCESS', value);
  }, function(reason) {
    console.log(reason);
  })
```


## Run tests

First, make sure that you have all dependencies installed. Run (only once):
```bash
npm i
```

Run tests:
```bash
npm test
```
