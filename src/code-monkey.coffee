recast = require 'recast'
types  = require 'ast-types'
_      = require 'lodash'

class MarkovGrammar
  @recase : (str) ->
    return str.substring(0,1).toLowerCase() + str.substring(1)

  @extractType : (node) ->
    # Special handling for literals and identifiers
    if node.type is 'Literal' and node.regex?
      return [node.raw, node.regex]
    else if node.type is 'Literal'
      return [node.value]
    else if node.type is 'Identifier'
      return [node.name]

    children = []
    for field in types.getFieldNames(node)
      continue if field is 'type' # prevent loops
      continue if field is 'computed' # prevent loops
      continue if field is 'guardedHandlers' # prevent errors
      child = types.getFieldValue(node, field)

      if not child?
        children.push child
      else if _.isArray(child)
        children.push _.map(child, 'type')
      else if not child.type?
        children.push child
      else
        children.push child.type

    return children

  constructor : ->
    @reset()

  reset : ->
    @cfg = {}

  learn : (ast) ->
    cfg = @cfg
    types.visit(ast, {
      visitNode : (path) ->
        {node, value} = path
        cfg[node.type] ?= []
        cfg[node.type].push MarkovGrammar.extractType(value)
        @traverse(path)
    })

  expand : (type) =>
    # Expand nodes if arg is an Array
    if _.isArray(type)
      return _.map(type, @expand)

    # Construct AST node if valid type
    else if @cfg[type]?.length > 0
      child = _.sample(@cfg[type])
      if type is 'Identifier'
        # Construct Identifier
        return types.builders.identifier.apply(types.builders, child)
      else if type is 'Literal'
        # Construct Literal
        return types.builders.literal.apply(types.builders, child)
      else
        # Construct AST node with recursive nodes as arguments
        args    = _.map(child, @expand)
        builder = types.builders[MarkovGrammar.recase(type)]
        return builder.apply(types.builders, args)

    # Otherwise return literal value
    else
      return type

class GrammarSampler
  @DEFAULT_ROOT_NODES : [
    # Make functions more common
    'FunctionDeclaration'
    'FunctionDeclaration'
    'FunctionDeclaration'
    'FunctionExpression'
    'FunctionExpression'
    'FunctionExpression'

    # A few general expressions
    'ExpressionStatement'
    'ExpressionStatement'
    'ExpressionStatement'

    # Other valid statements
    'IfStatement'
    'ForInStatement'
    'VariableDeclaration'
  ]

  constructor : ->
    @gen = new MarkovGrammar()

  learn : (code) ->
    @gen.learn(recast.parse(code))

  cfg : (cfg) ->
    if cfg? then @gen.cfg = cfg
    return @gen.cfg

  generate : (roots = GrammarSampler.DEFAULT_ROOT_NODES) ->
    root = _.sample(roots)
    try
      node = @gen.expand(root)
      return recast.print(node, {tabWidth : 2}).code
    catch e
      # console.error e # for debugging
      return '/* :-) */' # Secret error string

  generateLines : (min = 1) ->
    lines = []
    length = 0
    while length < min
      l = @generate().split('\n')
      l.push ''
      length += l.length
      lines.push l
    return _.flatten(lines)


class StringTyper
  constructor : (@_callback, @_delay = 80) ->
    @_str       = ''
    @_index     = 0
    @_variation = @_delay * 0.5

  push : (str) ->
    @_str += str
    @checkString()

  hasString : ->
    return @_index < @_str.length

  checkString : ->
    if @hasString()
      timeout = @_delay + @_variation * (2 * Math.random() - 1.0)
      setTimeout(@_next, timeout)
    else
      @_callback('\n\n')
      @onEmpty?()
    return

  _next : =>
    @_callback(@_str[@_index++])
    @checkString()
    return


stats = (fn) ->
  start  = new Date().getTime()
  result = fn()
  count  = result.length
  msec   = new Date().getTime() - start
  speed  = Math.round(1000 * count / msec)
  return {result, count, msec, speed}


if require?.main is module then do ->
  opts = require 'commander'
  opts
    .description('''
      Generate endless fake javascript.

      Just point this utility at a javascript file. It will parse and measure
      the frequency of the nodes in its abstract syntax tree. Then, we
      randomly sample a node's children until we have a valid AST node. Then,
      we generate javascript from the node.
    ''')
    .option('--src <source>', 'Source Javascript (.js) or Context Free Grammar (.json)')
    .option('--min <min>', 'Specify minumum number of lines. A value of 0 will loop forever.', parseInt)
    .option('--type', 'Type the output as if from keyboard input')
    .option('--stats', 'Show stats for code generation (requires --min)')
    .option('--cfg', 'Output Context Free Grammar JSON to console. This allows you to pre-compute the parsing step')
    .parse(process.argv)

  opts.help() unless opts.src

  gen = new GrammarSampler()

  # Load sampled grammar
  if /.js$/.test opts.src
    fs = require 'fs'
    gen.learn(fs.readFileSync(opts.src))
  else if /.json$/.test opts.src
    gen.cfg(require "./#{opts.src}")
  else
    opts.help()

  # Ouput context free grammar
  if opts.cfg
    console.log JSON.stringify(gen.cfg(), null, 2)

  # Output stats
  else if opts.min and opts.stats
    fn = -> gen.generateLines(opts.min)
    {count, msec, speed} = stats(fn)
    console.log "Generated #{count} lines in #{msec} msec. Speed: #{speed} lines/sec"

  # Output generated code
  else

    # Prepare output methods
    if opts.type
      typer   = new StringTyper((char) -> process.stdout.write(char))
      output  = (str) -> typer.push(str)
      forever = (fn) ->
        typer.onEmpty = fn
        typer.checkString()
    else
      output  = console.log
      forever = (fn) -> setInterval(fn, 0)

    # Generate
    if opts.min is 0
      forever -> output gen.generate()
    else if opts.min?
      output gen.generateLines(opts.min).join('\n')
    else
      output gen.generate()

else
  exports = {
    MarkovGrammar
    GrammarSampler
    StringTyper
  }
  module?.exports    = exports
  window?.codeMonkey = exports
