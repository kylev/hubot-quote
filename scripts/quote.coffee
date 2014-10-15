# Description:
#   Remember messages and quote them back
#
# Commands:
#   hubot remember <user> <text> - remember most recent message from <user> containing <text>
#   hubot quote <user> <text> - quote a random remembered message from <user> containing <text>
#   hubot forget <user> <text> - forget most recent remembered message from <user> containing <text>
#   hubot quotemash <text> - quote some random remembered messages containing <text>

Util = require 'util'
_ = require 'underscore'
natural = require 'natural'

stemmer = natural.PorterStemmer

CACHE_SIZE = 25
STORE_SIZE = 100

uniqueStems = (text) ->
  return _.unique(stemmer.tokenizeAndStem(text))

module.exports = (robot) ->
  robot.brain.setAutoSave(true)
  robot.brain.set('quoteMessageCache', {})
  robot.brain.set('quoteMessageStore', {})

  hubotMessageRegex = new RegExp('^[@]?' + robot.name + '[:,]?\\s', 'i')

  messageToString = (message) ->
    return "#{message.user.name}: #{message.text}"

  robot.respond /remember (\w*) (.*)/i, (msg) ->
    username = msg.match[1]
    text = msg.match[2]

    stems = uniqueStems(text)

    messageCache = robot.brain.get('quoteMessageCache')
    messageStore = robot.brain.get('quoteMessageStore')

    #TODO search for users in messageStore in case they've been removed? (name change implications?)
    users = robot.brain.usersForFuzzyName(username)

    message = null

    _.find users, (user) ->
      if messageCache[user.id] is undefined
        return false
      else
        messageIdx = null
        message = _.find messageCache[user.id], (msg, idx) ->
          messageIdx = idx
          #cache stems on message
          msg.stems = msg.stems or uniqueStems(msg.text)
          return _.intersection(stems, msg.stems).length is stems.length

        if message
          messageStore[user.id] = messageStore[user.id] or []
          messageStore[user.id].unshift(message)

          messageCache[user.id].splice(messageIdx, 1)

          robot.brain.set('quoteMessageStore', messageStore)
          robot.brain.set('quoteMessageCache', messageCache)

          #TODO configurable responses
          msg.send("remembering " + messageToString(message))

        return message

    if users.length is 0
      msg.send("#{username} not found")
    else if not message
      msg.send("#{text} not found")

  robot.respond /forget (\w*) (.*)/i, (msg) ->
    username = msg.match[1]
    text = msg.match[2]

    messageStore = robot.brain.get('quoteMessageStore')

    users = robot.brain.usersForFuzzyName(username)

    message = null

    _.find users, (user) ->
      if messageStore[user.id] is undefined
        return false
      else
        messageIdx = null
        message = _.find messageStore[user.id], (msg, idx) ->
          messageIdx = idx
          return msg.text.indexOf(text) isnt -1
        
        if message
          messageStore[user.id].splice(messageIdx, 1)
          robot.brain.set('quoteMessageStore', messageStore)
          #TODO message object with toString
          msg.send("forgot " + messageToString(message))

        return message

    if users.length is 0
      msg.send("#{username} not found")
    else if not message
      msg.send("#{text} not found")

  robot.respond /quote (\w*) (.*)/i, (msg) ->
    username = msg.match[1]
    text = msg.match[2]

    stems = uniqueStems(text)

    messageStore = robot.brain.get('quoteMessageStore')

    users = robot.brain.usersForFuzzyName(username)

    messages = null

    _.find users, (user) ->
      if messageStore[user.id] is undefined
        return false
      else
        messages = _.filter messageStore[user.id], (msg) ->
          #require all words to be present
          #TODO more permissive search?
          return _.intersection(stems, msg.stems).length is stems.length

        if messages and messages.length > 0
          message = messages[_.random(messages.length - 1)]
          msg.send(messageToString(message))

        return messages and messages.length > 0

    if users.length is 0
      msg.send("#{username} not found")
    else if not messages or messages.length is 0
      msg.send("#{text} not found")

  robot.respond /quotemash (.*)/i, (msg) ->
    text = msg.match[1]
    limit = 10

    stems = uniqueStems(text)

    messageStore = robot.brain.get('quoteMessageStore')

    matches = _.flatten _.map messageStore, (messages) ->
      return _.filter messages, (msg) ->
        return _.intersection(stems, msg.stems).length is stems.length

    messages = []

    if matches and matches.length > 0
      while messages.length < limit and matches.length > 0
        messages.push(matches.splice(_.random(matches.length - 1), 1)[0])

      msg.send.apply(msg, _.map(messages, messageToString))
    else
      msg.send("#{text} not found")

  robot.hear /.*/, (msg) ->
    #TODO existing way to test this somewhere??
    if not hubotMessageRegex.test(msg.message.text)
      userId = msg.message.user.id
      messageCache = robot.brain.get('quoteMessageCache')

      messageCache[userId] = messageCache[userId] or []

      if messageCache[userId].length is CACHE_SIZE
        messageCache[userId].pop()

      #TODO configurable cache size
      messageCache[userId].unshift({
        text: msg.message.text,
        user: msg.message.user
      })

      robot.brain.set('quoteMessageCache', messageCache)

