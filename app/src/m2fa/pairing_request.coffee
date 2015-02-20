
@ledger.m2fa ?= {}

###
  Wrapper around the pairing API. The pairing request ensures process consistency and will complete with a failure if any
  of the protocol step is broken. The pairing request fire events in order to follow up the current step and provide an
  internal state.

  @event 'join' Notifies that a client joined the room and attempts to create a secure channel
  @event 'sendChallenge' Notifies that the dongle is challenging the client
  @event 'answerChallenge' Notifies that a client answered to the dongle challenge

###
class @ledger.m2fa.PairingRequest extends @EventEmitter

  @States:
    WAITING: 0
    CHALLENGING: 1
    FINISHING: 2
    DEAD: 3

  @Errors:
    InconsistentState: "Inconsistent state"
    ClientCancelled: "Client cancelled: consider power cycling your dongle"
    NeedPowerCycle: "Dongle needs to be power cycled"
    InvalidChallengeResponse: "Invalid challenge response"
    Cancelled: "Cancelled"
    UnknownError: "Unknown error"

  constructor: (pairindId, promise, client) ->
    @pairingId = pairindId
    @_client = client
    @_pairedDongleName = new CompletionClosure()
    @_client.pairedDongleName = @_pairedDongleName
    @_currentState = ledger.m2fa.PairingRequest.States.WAITING

    promise.then(
      (result) =>
        @_success(result)
      ,
      (err) ->
        failure = switch err
          when 'invalidChallenge' then ledger.m2fa.PairingRequest.Errors.InvalidChallengeResponse
          when 'cancel' then ledger.m2fa.PairingRequest.Errors.Cancelled
          when 'initiateFailure' then ledger.m2fa.PairingRequest.Errors.NeedPowerCycle
          else ledger.m2fa.PairingRequest.Errors.UnknownError
        @_failure(failure)
      ,
      (progress) =>
        switch progress
          when 'pubKeyReceived'
            return _failure(ledger.m2fa.PairingRequest.Errors.InconsistentState) if @_currentState isnt ledger.m2fa.PairingRequest.States.WAITING
            @_currentState = ledger.m2fa.PairingRequest.States.CHALLENGING
            @emit 'join'
          when 'challengeReceived'
            return _failure(ledger.m2fa.PairingRequest.Errors.InconsistentState) if @_currentState isnt ledger.m2fa.PairingRequest.States.CHALLENGING
            @_currentState = ledger.m2fa.PairingRequest.States.FINISHING
            @emit 'answerChallenge'
          when 'secureScreenDisconnect'
            @_failure(ledger.m2fa.PairingRequest.Errors.ClientCancelled) if @_currentState isnt ledger.m2fa.PairingRequest.States.WAITING
          when 'sendChallenge' then @emit 'challenge'
    ).done()
    @_client.on 'm2fa.disconnect'
    @_promise = promise

  # Sets the completion callback.
  # @param [Function] A callback to call once the pairing process is completed
  onComplete: (cb) -> @_onComplete = cb

  # Sets the dongle name. This is a mandatory step for saving the paired secure screen
  setDongleName: (name) -> @_pairedDongleName.success(name)

  getCurrentState: () -> @_currentState

  cancel: () ->
    @_promise = null
    @_pairedDongleName.fail('cancel')
    @_client.stopIfNeccessary()
    @_onComplete = null
    @emit 'cancel'

  _failure: (reason) ->
    @_currentState = ledger.m2fa.PairingRequest.States.DEAD
    @_onComplete.fail(reason) unless @_onComplete.isCompleted()

  _success: (screen) ->
    @_currentState = ledger.m2fa.PairingRequest.States.DEAD
    @_onComplete.success(dongle) unless @_onComplete.isCompleted()