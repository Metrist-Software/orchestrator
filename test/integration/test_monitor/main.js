"use strict"

const p = require('@metrist/protocol')

const proto = new p.Protocol()
const steps = {}

steps.TestLogging = async function() {
  proto.logDebug('Test Logging: DEBUG')
  proto.logInfo('Test Logging: INFO')
  proto.logError('Test Logging: ERROR')
  proto.sendTime(2.0)
}

steps.Error = async function() {
  throw 'Error!'
}

steps.PrintStderr = async function() {
  console.error('On stderr')
  proto.sendOK()
}

const main = async function() {
  await proto.handshake(async (_config) => {})
  let cleanupHandler = async () => {}
  let teardownHandler = async () => {}

  let step = null
  while ((step = await proto.getStep(cleanupHandler, teardownHandler)) != null) {
    await steps[step]()
      .catch(e => proto.sendError(e))
  }
  process.exit(0)
}

main()
