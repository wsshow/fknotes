package com.fknotes.app

internal object LiteRtLmIpc {
    const val LOAD = 1
    const val GENERATE = 2
    const val CANCEL = 3
    const val UNLOAD = 4
    const val EVENT = 100

    const val REQUEST_ID = "requestId"
    const val PAYLOAD = "payload"
    const val TYPE = "type"
    const val DATA = "data"
}
