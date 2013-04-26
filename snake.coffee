INIT_FPS = 200
WIDTH = 20
HEIGHT = 20
CANVAS_WIDTH = 500
CANVAS_HEIGHT = 500
FIELD_AREA = HEIGHT * WIDTH
W_SCALE = CANVAS_WIDTH / WIDTH
H_SCALE = CANVAS_HEIGHT / HEIGHT
[UP, DOWN, LEFT, RIGHT] = ["u", "d", "l", "r"]

rgba = (r, g, b, a) -> "rgba(#{r}, #{g}, #{b}, #{a})"
# [start, end)
randInt = (start, end) -> Math.floor Math.random() * (end - start) + start
isOpposite = (d1, d2) ->
  switch d1
    when UP
      if d2 is DOWN then true else false
    when DOWN
      if d2 is UP then true else false
    when LEFT
      if d2 is RIGHT then true else false
    when RIGHT
      if d2 is LEFT then true else false
    else throw new Error("Invalid direction #{d1}")

class Point
  constructor: (@x, @y) ->
  add: (x, y) -> new Point @x + x, @y + y
  equals: (other) -> @x is other.x and @y is other.y
  toString: -> "(#{@x}, #{@y})"

class Snake
  constructor: (head) ->
    @body = [head]
    @direction = RIGHT
  head: -> @body[0]
  tail: -> @body[@body.length - 1]
  fork: ->
    snake = new Snake(new Point 0, 0)
    # copy array
    snake.body = @body.slice 0
    snake.direction = @direction
    return snake
  advance: (command) ->
    # do nothing if opposite
    command = @direction if isOpposite command, @direction
    nextHead = Game.adjacentCell command, @head()
    @body.unshift nextHead
    @direction = command
  move: (command) ->
    command = @direction if isOpposite command, @direction
    @advance command
    @moveTail()
  moveTail: -> @body.pop()
  bodyHit: ->
    # skip head
    for seg in @body[1...@body.length]
      return true if @head().equals seg
    return false
  wallHit: -> not (0 <= @head().x < WIDTH and 0 <= @head().y < HEIGHT)

PathNotFoundError = {}

class Game
  @adjacentCell = (direction, cell) ->
    switch direction.toLowerCase()
      when 'u' then cell.add 0, -1
      when 'd' then cell.add 0, 1
      when 'l' then cell.add -1, 0
      when 'r' then cell.add 1, 0
      else throw new Error "Invalid direction #{direction}"

  constructor: (@ctx) ->
    @fps = INIT_FPS
    @food = new Point 3, 3
    @score = 0
    @snake = new Snake(new Point 1, 1)
    @commands = []
    @map = (null for i in [0...HEIGHT] for j in [0...WIDTH])
    @marks = (false for i in [0...HEIGHT] for j in [0...WIDTH])
  draw: ->
    @ctx.clearRect 0, 0, CANVAS_WIDTH, CANVAS_HEIGHT
    # draw snake
    for i in [0...@snake.body.length]
      seg = @snake.body[i]
      @ctx.fillStyle = rgba 133, 22, 88, 1 - 0.7 * (i / @snake.body.length)
      @ctx.fillRect seg.x * W_SCALE, seg.y * H_SCALE, W_SCALE, H_SCALE
    # draw food
    @ctx.fillStyle = "yellow"
    @ctx.fillRect @food.x * W_SCALE, @food.y * H_SCALE, W_SCALE, H_SCALE
  placeFood: ->
    while true
      food = new Point randInt(0, WIDTH), randInt(0, HEIGHT)
      if (@snake.body.every (s) -> not s.equals food)
        # FIXME: this is for debug
        @lastFood = @food
        @food = food
        break
  onTick: ->
    if @commands.length is 0
      @commands = Array.prototype.slice.apply @makeMoves()
    @snake.advance @commands.shift()
    # always update score
    $(this).trigger "updateInfo", "Score: #{@score}"
    # check food
    if @snake.head().equals @food
      @placeFood()
      @score++
    else
      # move tail too
      @snake.moveTail()
    # game over?
    if @snake.wallHit() or @snake.bodyHit()
      @stop()
      $(this).trigger "updateInfo", "GAME OVER"
      return
    # Unbeliveable!
    if @snake.body.length >= WIDTH * HEIGHT - 1
      @stop()
      $(this).trigger "updateInfo", "Unbelievable!"
      return
    # redraw
    @draw()
    #@ticker = setTimeout @onTick.bind this, 1000 / @fps i
    @ticker = setTimeout (=> @onTick()), 1000 / @fps
  play: -> @onTick()
  stop: -> clearTimeout @ticker

  isCellFree: (cell, snake) ->
    0 <= cell.x < WIDTH and 0 <= cell.y < HEIGHT \
                        and snake.body.every (s) -> not s.equals cell

  # path to food
  findPathToCell: (snake, dest) ->
    head = snake.head()
    @marks[j][i] = false for i in [0...HEIGHT] for j in [0...WIDTH]
    # BFS queue
    queue = [new SearchState head]
    while queue.length isnt 0
      node = queue.shift()
      continue if @marks[node.head.x][node.head.y] is true
      @marks[node.head.x][node.head.y] = true
      # expand node
      for dir in [UP, DOWN, LEFT, RIGHT]
        cell = Game.adjacentCell dir, node.head
        return node.traceCmd() + dir if cell.equals dest
        queue.push new SearchState cell, dir, node if @isCellFree cell, snake
    throw PathNotFoundError

  followTail: (snake) ->
    # from tail to head
    head = snake.head()
    tail = snake.tail()
    @map[j][i] = null for i in [0...HEIGHT] for j in [0...WIDTH]
    @map[tail.x][tail.y] = 0
    @marks[j][i] = false for i in [0...HEIGHT] for j in [0...WIDTH]
    queue = [tail]
    found = false
    while queue.length isnt 0
      node = queue.shift()
      continue if @marks[node.x][node.y] is true
      @marks[node.x][node.y] = true
      # expand node
      for dir in [UP, DOWN, LEFT, RIGHT]
        cell = Game.adjacentCell dir, node
        found = true if cell.equals head
        if @isCellFree cell, snake
          if @map[cell.x][cell.y] is null
            @map[cell.x][cell.y] = @map[node.x][node.y] + 1
          queue.push cell
    if found
      # follow the longest path
      max = -1
      move = null
      for dir in [UP, DOWN, LEFT, RIGHT]
        next = Game.adjacentCell dir, head
        if @isCellFree(next, snake) or next.equals tail
          if @map[next.x][next.y] > max and @map[next.x][next.y] isnt null
            max = @map[next.x][next.y]
            move = dir
      return move
    else
      throw PathNotFoundError

  # AI entry
  makeMoves: ->
    # manual mode
    try
      path = @findPathToCell @snake, @food
      fork = @snake.fork()
      for cmd in path
        fork.advance cmd
        fork.moveTail() unless fork.head().equals @food
      # can reach tail?
      @findPathToCell fork, fork.tail()
      return path
    catch e
      if e is PathNotFoundError
        # follow tail
        try
          return @followTail @snake
        catch e
          if e is PathNotFoundError
            # cannot even reach tail, thus we make random possible move
            for direction in [UP, DOWN, LEFT, RIGHT]
              next = Game.adjacentCell direction, @snake.head()
              return direction if @isCellFree next, @snake
            # move forward and die hard
            return @snake.direction
          else
            throw e
      else
        throw e

class SearchState
  constructor: (@head, @cmd='', @parent=null) ->
  traceCmd: -> if @parent is null then @cmd else @parent.traceCmd() + @cmd
  toString: -> "#{@head}, '#{@traceCmd()}'"

$(document).ready ->
  context = $('.main_canvas')[0].getContext '2d'
  game = new Game(context)
  $(game).on 'updateInfo', (e, info) -> $('#score').text(info)
  game.play()
