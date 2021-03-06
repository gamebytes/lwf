#
# Copyright (C) 2012 GREE, Inc.
#
# This software is provided 'as-is', without any express or implied
# warranty.  In no event will the authors be held liable for any damages
# arising from the use of this software.
#
# Permission is granted to anyone to use this software for any purpose,
# including commercial applications, and to alter it and redistribute it
# freely, subject to the following restrictions:
#
# 1. The origin of this software must not be misrepresented; you must not
#    claim that you wrote the original software. If you use this software
#    in a product, an acknowledgment in the product documentation would be
#    appreciated but is not required.
# 2. Altered source versions must be plainly marked as such, and must not be
#    misrepresented as being the original software.
# 3. This notice may not be removed or altered from any source distribution.
#

class WebGLRenderCommand
  constructor:(context, texture, matrix) ->
    @renderCount = 0
    @renderingIndex = 0
    @context = context
    @texture = texture
    @matrix = matrix
    @colorTransform = null
    @blendMode = 0
    @maskMode = 0

class WebGLRendererContext
  constructor: ->
    @refCount = 1
    @glContext = null
    @textures = {}
    @vertexBuffer = null
    @indexBuffer = null
    @aVertexPosition = null
    @aTextureCoord = null
    @uPMatrix = null
    @uMatrix = null
    @uTexture = null

class WebGLRendererFactory extends WebkitCSSRendererFactory
  @rendererContexts = {}

  initGL: ->
    rendererContext = WebGLRendererFactory.rendererContexts[@stage.id]
    if rendererContext?
      ++rendererContext.refCount
      @glContext = rendererContext.glContext
      @textures = rendererContext.textures
      @vertexBuffer = rendererContext.vertexBuffer
      @indexBuffer = rendererContext.indexBuffer
      @aVertexPosition = rendererContext.aVertexPosition
      @aTextureCoord = rendererContext.aTextureCoord
      @aColor = rendererContext.aColor
      @uPMatrix = rendererContext.uPMatrix
      @uMatrix = rendererContext.uMatrix
      @uTexture = rendererContext.uTexture
      return

    rendererContext = new WebGLRendererContext()
    @textures = rendererContext.textures
    WebGLRendererFactory.rendererContexts[@stage.id] = rendererContext

    @stage.style.webkitUserSelect = "none"
    if @stage.width is 0 and @stage.height is 0
      @stage.width = @data.header.width
      @stage.height = @data.header.height

    params =
      alpha:false
      antialias:false
      depth:false
      premultipliedAlpha:true
      preserveDrawingBuffer:false
    @glContext = @stage.getContext("webgl", params) ?
      @stage.getContext("experimental-webgl", params)
    rendererContext.glContext = @glContext

    gl = @glContext
    @vertexBuffer = gl.createBuffer()
    @indexBuffer = gl.createBuffer()
    rendererContext.vertexBuffer = @vertexBuffer
    rendererContext.indexBuffer = @indexBuffer
    @bindVertexBuffer(gl, @vertexBuffer)
    @bindIndexBuffer(gl, @indexBuffer)

    if @useVertexColor
      vertexShader = @loadShader(gl, gl.VERTEX_SHADER, """
        attribute vec2 aVertexPosition;
        attribute vec2 aTextureCoord;
        attribute vec4 aColor;
        uniform mat4 uPMatrix;
        uniform mat4 uMatrix;
        varying vec2 vTextureCoord;
        varying vec4 vColor;
        void main() {
          gl_Position = uPMatrix * uMatrix * vec4(aVertexPosition, 0, 1);
          vTextureCoord = aTextureCoord;
          vColor = aColor;
        }
        """)

      fragmentShader = @loadShader(gl, gl.FRAGMENT_SHADER, """
        precision mediump float;
        varying vec2 vTextureCoord;
        varying vec4 vColor;
        uniform sampler2D uTexture;
        void main() {
          gl_FragColor = vColor * texture2D(uTexture, vTextureCoord);
        }
        """)
    else
      vertexShader = @loadShader(gl, gl.VERTEX_SHADER, """
        attribute vec2 aVertexPosition;
        attribute vec3 aTextureCoord;
        uniform mat4 uPMatrix;
        uniform mat4 uMatrix;
        varying vec3 vTextureCoord;
        void main() {
          gl_Position = uPMatrix * uMatrix * vec4(aVertexPosition, 0, 1);
          vTextureCoord = aTextureCoord;
        }
        """)

      fragmentShader = @loadShader(gl, gl.FRAGMENT_SHADER, """
        precision mediump float;
        varying vec3 vTextureCoord;
        uniform sampler2D uTexture;
        void main() {
          gl_FragColor = vec4(1, 1, 1, vTextureCoord.z) * texture2D(uTexture, vTextureCoord.xy);
        }
        """)

    shaderProgram = gl.createProgram()
    gl.attachShader(shaderProgram, vertexShader)
    gl.attachShader(shaderProgram, fragmentShader)
    gl.linkProgram(shaderProgram)
    unless gl.getProgramParameter(shaderProgram, gl.LINK_STATUS)
      alert("Unable to initialize the shader program.")
    gl.useProgram(shaderProgram)

    @aVertexPosition = gl.getAttribLocation(shaderProgram, "aVertexPosition")
    @aTextureCoord = gl.getAttribLocation(shaderProgram, "aTextureCoord")
    @uPMatrix = gl.getUniformLocation(shaderProgram, "uPMatrix")
    @uMatrix = gl.getUniformLocation(shaderProgram, "uMatrix")
    @uTexture = gl.getUniformLocation(shaderProgram, "uTexture")
    rendererContext.aVertexPosition = @aVertexPosition
    rendererContext.aTextureCoord = @aTextureCoord
    rendererContext.uPMatrix = @uPMatrix
    rendererContext.uMatrix = @uMatrix
    rendererContext.uTexture = @uTexture

    vertexBufferSize = 4 * @attributes
    gl.vertexAttribPointer(
      @aVertexPosition, 2, gl.FLOAT, false, vertexBufferSize, 0)
    gl.vertexAttribPointer(@aTextureCoord, (if @useVertexColor then 2 else 3),
      gl.FLOAT, false, vertexBufferSize, 8)

    gl.enableVertexAttribArray(@aVertexPosition)
    gl.enableVertexAttribArray(@aTextureCoord)

    if @useVertexColor
      @aColor = gl.getAttribLocation(shaderProgram, "aColor")
      rendererContext.aColor = @aColor
      gl.vertexAttribPointer(@aColor, 4, gl.FLOAT, false, vertexBufferSize, 16)
      gl.enableVertexAttribArray(@aColor)

    gl.enable(gl.BLEND)
    gl.disable(gl.DEPTH_TEST)
    gl.disable(gl.DITHER)
    gl.disable(gl.SCISSOR_TEST)
    gl.activeTexture(gl.TEXTURE0)
    gl.clearColor(0.0, 0.0, 0.0, 1.0)
    return

  destructGL: ->
    rendererContext = WebGLRendererFactory.rendererContexts[@stage.id]
    return if --rendererContext.refCount > 0

    gl = @glContext
    gl.deleteBuffer(@indexBuffer)
    gl.deleteBuffer(@vertexBuffer)
    gl.deleteTexture(d[0]) for k, d in @textures
    delete WebGLRendererFactory.rendererContexts[@stage.id]
    return

  loadShader:(gl, type, program) ->
    shader = gl.createShader(type)
    gl.shaderSource(shader, program)
    gl.compileShader(shader)
    unless gl.getShaderParameter(shader, gl.COMPILE_STATUS)
      alert("An error occurred compiling the shaders: " +
        gl.getShaderInfoLog(shader))
    return shader

  setTexParameter:(gl, repeatS = false, repeatT = false) ->
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S,
      if repeatS then gl.REPEAT else gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T,
      if repeatT then gl.REPEAT else gl.CLAMP_TO_EDGE)
    return

  setViewport:(gl, lwf) ->
    changed = @propertyMatrix.setWithComparing(lwf.property.matrix)
    if changed or @w isnt @stage.width or @h isnt @stage.height
      @w = @stage.width
      @h = @stage.height
      gl.viewport(0, 0, @w, @h)
      #gl.scissor(@propertyMatrix.translateX, @propertyMatrix.translateY,
      #  @data.header.width * @propertyMatrix.scaleX,
      #  @data.header.height * @propertyMatrix.scaleY)

      right = @w
      left = 0
      top = 0
      bottom = @h
      far = 1
      near = -1
      pmatrix = new Float32Array([
        2 / (right - left), 0, 0, 0,
        0, 2 / (top - bottom), 0, 0,
        0, 0, -2 / (far - near), 0,
        -(right + left) / (right - left), -(top + bottom) / (top - bottom),
          -(far + near) / (far - near), 1
      ])
      gl.uniformMatrix4fv(@uPMatrix, false, pmatrix)
    return

  constructor:(@data, @resourceCache,
      @cache, @stage, @textInSubpixel, @needsClear, @useVertexColor) ->
    @attributes = if @useVertexColor then 8 else 5
    @initGL()
    @drawCalls = 0
    @blendMode = "normal"
    @maskMode = "normal"
    @matrix = new Float32Array([1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1])
    @propertyMatrix = new Matrix
    @vertexData = new Float32Array(1)
    @indexData = new Uint16Array(1)
    @color = new Float32Array(4)
    @backGroundColor = [0, 0, 0, 1]

    @bitmapContexts = []
    for bitmap in data.bitmaps
      continue if bitmap.textureFragmentId is -1
      bitmapEx = new Format.BitmapEx()
      bitmapEx.matrixId = bitmap.matrixId
      bitmapEx.textureFragmentId = bitmap.textureFragmentId
      bitmapEx.u = 0
      bitmapEx.v = 0
      bitmapEx.w = 1
      bitmapEx.h = 1
      bitmapEx.attribute = 0
      @bitmapContexts.push new WebGLBitmapContext(@, data, bitmapEx)

    @bitmapExContexts = []
    for bitmapEx in data.bitmapExs
      continue if bitmapEx.textureFragmentId is -1
      @bitmapExContexts.push new WebGLBitmapContext(@, data, bitmapEx)

    @textContexts = []
    for text in data.texts
      @textContexts.push new WebGLTextContext(@, data, text)

    @initCommands()

  destruct: ->
    @bindedTexture = null
    @currentTexture = null
    @deleteMask(@glContext)
    @destructGL()
    context.destruct() for context in @bitmapContexts
    context.destruct() for context in @bitmapExContexts
    context.destruct() for context in @textContexts
    return

  beginRender:(lwf) ->
    super(lwf)
    @lwf = lwf
    return if lwf.parent?
    @faces = 0
    return

  bindTexture:(gl, texture) ->
    if @bindedTexture isnt texture
      gl.bindTexture(gl.TEXTURE_2D, texture)
      @bindedTexture = texture
    return

  blendFunc:(gl, blendSrcFactor, blendDstFactor) ->
    if @setSrcFactor isnt blendSrcFactor or @setDstFactor isnt blendDstFactor
      @setSrcFactor = blendSrcFactor
      @setDstFactor = blendDstFactor
      gl.blendFunc(blendSrcFactor, blendDstFactor)
    return

  bindVertexBuffer:(gl, buffer) ->
    if @bindedVertexBuffer isnt buffer
      @bindedVertexBuffer = buffer
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
    return

  bindIndexBuffer:(gl, buffer) ->
    if @bindedIndexBuffer isnt buffer
      @bindedIndexBuffer = buffer
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer)
    return

  setClearColor:(gl) ->
    [r, g, b, a] = @backGroundColor
    gl.clearColor(r / 255, g / 255, b / 255, a / 255)
    return

  addCommand:(rIndex, cmd) ->
    super(rIndex, cmd)
    return if @lwf.parent?
    ++@faces
    return

  endRender:(lwf) ->
    if lwf.parent?
      @addCommandToParent(lwf)
      return

    @currentTexture = null
    @bindedTexture = null
    @setSrcFactor = null
    @setDstFactor = null
    @bindedVertexBuffer = null
    @bindedIndexBuffer = null
    @currentBlendMode = "normal"
    gl = @glContext
    @setViewport(gl, lwf)
    gl.clear(gl.COLOR_BUFFER_BIT) if @needsClear

    vertices = @faces * 4 * @attributes
    @faces = 0
    @drawCalls = 0
    if vertices > @vertexData.length #or vertices < @vertexData.length / 6
      vertices *= 3
      vertices = 65536 * @attributes if vertices > 65536 * @attributes
      indices = vertices / (4 * @attributes) * 6
      if vertices isnt @vertexData.length
        @vertexData = new Float32Array(vertices)

        @indexData = new Uint16Array(indices)
        offset = 0
        indexOffset = 0
        for i in [0...indices / 6]
          @indexData[offset + 0] = indexOffset + 0
          @indexData[offset + 1] = indexOffset + 1
          @indexData[offset + 2] = indexOffset + 2
          @indexData[offset + 3] = indexOffset + 2
          @indexData[offset + 4] = indexOffset + 1
          @indexData[offset + 5] = indexOffset + 3
          offset += 6
          indexOffset += 4
        @bindIndexBuffer(gl, @indexBuffer)
        gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @indexData, gl.STATIC_DRAW)

    @renderMaskMode = "normal"
    @renderMasked = false

    renderCount = lwf.renderCount
    for rIndex in [0...@commands.length]
      cmd = @commands[rIndex]
      continue if !cmd? or cmd.renderingIndex isnt rIndex or
        cmd.renderCount isnt renderCount
      if cmd.subCommands?
        for srIndex in [0...cmd.subCommands.length]
          scmd = cmd.subCommands[srIndex]
          continue if !scmd? or scmd.renderingIndex isnt srIndex or
            scmd.renderCount isnt renderCount
          @render(gl, scmd)
      @render(gl, cmd)
    @renderMesh(gl)

    if @renderMaskMode isnt "normal"
      if @renderMaskMode is "layer" and @renderMasked
        @renderMask(gl)
      else
        gl.bindFramebuffer(gl.FRAMEBUFFER, null)

    @initCommands()
    return

  render:(gl, cmd) ->
    if @renderMaskMode isnt cmd.maskMode
      @renderMesh(gl)
      @generateMask(gl)
      switch cmd.maskMode
        when "erase", "mask"
          @renderMask(gl) if @renderMaskMode is "layer" and @renderMasked
          @renderMasked = true
          @maskSrcFactor = if cmd.maskMode is "erase" then \
            gl.ONE_MINUS_DST_ALPHA else gl.DST_ALPHA
          gl.bindFramebuffer(gl.FRAMEBUFFER, @maskFrameBuffer)
          gl.clearColor(0, 0, 0, 0)
          gl.clear(gl.COLOR_BUFFER_BIT)
          @setClearColor(gl)
        when "layer"
          if @renderMasked
            gl.bindFramebuffer(gl.FRAMEBUFFER, @layerFrameBuffer)
            gl.clearColor(0, 0, 0, 0)
            gl.clear(gl.COLOR_BUFFER_BIT)
            @setClearColor(gl)
          else
            gl.bindFramebuffer(gl.FRAMEBUFFER, null)
        else
          if @renderMaskMode is "layer" and @renderMasked
            @renderMask(gl)
          else
            gl.bindFramebuffer(gl.FRAMEBUFFER, null)
      @renderMaskMode = cmd.maskMode

    context = cmd.context
    texture = cmd.texture
    m = cmd.matrix
    c = cmd.colorTransform
    blendMode = cmd.blendMode

    if texture isnt @currentTexture or blendMode isnt @currentBlendMode or
        @faces * 4 * @attributes >= @vertexData.length
      @renderMesh(gl)
      @currentTexture = texture
      @currentBlendMode = blendMode
      @blendSrcFactor =
        if context.preMultipliedAlpha then gl.ONE else gl.SRC_ALPHA
      @blendDstFactor =
        if blendMode is "add" then gl.ONE else gl.ONE_MINUS_SRC_ALPHA

    ###
    alpha = c.multi.alpha
    if @useVertexColor
      red = c.multi.red
      green = c.multi.green
      blue = c.multi.blue
      if context.preMultipliedAlpha
        red *= alpha
        green *= alpha
        blue *= alpha
    else
      red = 1
      green = 1
      blue = 1
    ###
    cc = @color
    cc[3] = c.multi._[3]
    if @useVertexColor
      cc[0] = c.multi._[0]
      cc[1] = c.multi._[1]
      cc[2] = c.multi._[2]
      if context.preMultipliedAlpha
        cc[0] *= cc[3]
        cc[1] *= cc[3]
        cc[2] *= cc[3]

    ###
    scaleX = m.scaleX
    skew0 = m.skew0
    translateX = m.translateX

    skew1 = m.skew1
    scaleY = m.scaleY
    translateY = m.translateY

    translateZ = 0
    ###

    v = context.vertexData
    uv = context.uv
    mm0 = m._[0]
    mm1 = m._[1]
    mm2 = m._[2]
    mm3 = m._[3]
    mm4 = m._[4]
    mm5 = m._[5]
    alpha = cc[3]
    voffset = @faces++ * 4 * @attributes
    vertexData = @vertexData
    for i in [0...4]
      ###
      x = vertexData[i].x
      y = vertexData[i].y
      px = x * scaleX + y * skew0 + translateX
      py = x * skew1 + y * scaleY + translateY
      pz = translateZ
      ###
      x = i * 2 + 0
      y = i * 2 + 1
      vx = v[x]
      vy = v[y]
      uvx = uv[x]
      uvy = uv[y]

      offset = voffset + i * @attributes
      if @useVertexColor
        vertexData[offset + 0] = vx * mm0 + vy * mm2 + mm4 # px
        vertexData[offset + 1] = vx * mm1 + vy * mm3 + mm5 # py
        vertexData[offset + 2] = uvx # uv[i].u
        vertexData[offset + 3] = uvy # uv[i].v
        vertexData[offset + 4] = cc[0] # red
        vertexData[offset + 5] = cc[1] # green
        vertexData[offset + 6] = cc[2] # blue
        vertexData[offset + 7] = alpha
      else
        vertexData[offset + 0] = vx * mm0 + vy * mm2 + mm4 # px
        vertexData[offset + 1] = vx * mm1 + vy * mm3 + mm5 # py
        vertexData[offset + 2] = uvx # uv[i].u
        vertexData[offset + 3] = uvy # uv[i].v
        vertexData[offset + 4] = alpha
    return

  renderMesh:(gl) ->
    return if @currentTexture is null or @faces is 0

    @bindTexture(gl, @currentTexture)
    @blendFunc(gl, @blendSrcFactor, @blendDstFactor)

    if @bindedVertexBuffer is @vertexBuffer
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, @vertexData)
    else
      @bindVertexBuffer(gl, @vertexBuffer)
      gl.bufferData(gl.ARRAY_BUFFER, @vertexData, gl.DYNAMIC_DRAW)

    if @bindedIndexBuffer isnt @indexBuffer
      @bindIndexBuffer(gl, @indexBuffer)
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @indexData, gl.STATIC_DRAW)

    gl.uniformMatrix4fv(@uMatrix, false, @matrix)

    gl.drawElements(gl.TRIANGLES, @faces * 6, gl.UNSIGNED_SHORT, 0)
    @faces = 0
    ++@drawCalls
    return

  setBlendMode:(@blendMode) ->

  setMaskMode:(@maskMode) ->

  generateMask:(gl) ->
    return if @maskTexture? and
      @maskTextureWidth is @w and @maskTextureHeight is @h

    @maskMatrix = new Float32Array([1,0,0,0,0,-1,0,0,0,0,1,0,0,@h,0,1])

    @maskTexture = gl.createTexture()
    @maskTextureWidth = @w
    @maskTextureHeight = @h
    @layerTexture = gl.createTexture()
    textures = [@maskTexture, @layerTexture]
    @maskFrameBuffer = gl.createFramebuffer()
    @layerFrameBuffer = gl.createFramebuffer()
    framebuffers = [@maskFrameBuffer, @layerFrameBuffer]

    for i in [0...2]
      texture = textures[i]
      @bindTexture(gl, texture)
      gl.texImage2D(gl.TEXTURE_2D, 0,
        gl.RGBA, @w, @h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null)
      @setTexParameter(gl)

      framebuffer = framebuffers[i]
      gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer)
      gl.framebufferTexture2D(gl.FRAMEBUFFER,
        gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0)
      gl.bindFramebuffer(gl.FRAMEBUFFER, null)

    if @useVertexColor
      @maskVertexData = new Float32Array([
        #x,  y, u, v, r, g, b, a
        @w, @h, 1, 1, 1, 1, 1, 1,
        @w,  0, 1, 0, 1, 1, 1, 1,
         0, @h, 0, 1, 1, 1, 1, 1,
         0,  0, 0, 0, 1, 1, 1, 1,
      ])
    else
      @maskVertexData = new Float32Array([
        #x,  y, u, v, a
        @w, @h, 1, 1, 1,
        @w,  0, 1, 0, 1,
         0, @h, 0, 1, 1,
         0,  0, 0, 0, 1,
      ])
    return

  deleteMask:(gl) ->
    return unless @maskTexture?

    gl.deleteFramebuffer(@maskFrameBuffer)
    gl.deleteFramebuffer(@layerFrameBuffer)
    @maskFrameBuffer = null
    @layerFrameBuffer = null

    gl.deleteTexture(@maskTexture)
    gl.deleteTexture(@layerTexture)
    @maskTexture = null
    @layerTexture = null
    return

  renderMask:(gl) ->
    @bindVertexBuffer(gl, @vertexBuffer)
    @maskVertexData[@attributes * 0 + 0] = @w
    @maskVertexData[@attributes * 0 + 1] = @h
    @maskVertexData[@attributes * 1 + 0] = @w
    @maskVertexData[@attributes * 2 + 1] = @h
    if @bindedVertexBuffer is @vertexBuffer
      gl.bufferSubData(gl.ARRAY_BUFFER, 0, @maskVertexData)
    else
      @bindVertexBuffer(gl, @vertexBuffer)
      gl.bufferData(gl.ARRAY_BUFFER, @maskVertexData, gl.DYNAMIC_DRAW)

    @maskMatrix[13] = @h
    gl.uniformMatrix4fv(@uMatrix, false, @maskMatrix)

    @bindIndexBuffer(gl, @indexBuffer)
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @indexData, gl.STATIC_DRAW)
  
    gl.bindFramebuffer(gl.FRAMEBUFFER, @maskFrameBuffer)
    @bindTexture(gl, @layerTexture)
    @blendFunc(gl, @maskSrcFactor, gl.ZERO)
    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0)
    ++@drawCalls
  
    gl.bindFramebuffer(gl.FRAMEBUFFER, null)
    @bindTexture(gl, @maskTexture)
    @blendFunc(gl, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0)
    ++@drawCalls
    return

  constructBitmap:(lwf, objectId, bitmap) ->
    context = @bitmapContexts[objectId]
    new WebGLBitmapRenderer(context) if context

  constructBitmapEx:(lwf, objectId, bitmapEx) ->
    context = @bitmapExContexts[objectId]
    new WebGLBitmapRenderer(context) if context

  constructText:(lwf, objectId, text) ->
    context = @textContexts[objectId]
    new WebGLTextRenderer(lwf, context, text) if context

  constructParticle:(lwf, objectId, particle) ->
    ctor = @resourceCache.particleConstructor
    particleData = lwf.data.particleDatas[particle.particleDataId]
    ctor(lwf, lwf.data.strings[particleData.stringId]) if ctor?

  getStageSize: ->
    return [@stage.width, @stage.height]

  setBackgroundColor:(v) ->
    [r, g, b, a] = @parseBackgroundColor(v)
    @backGroundColor = [r, g, b, a]
    @setClearColor(@glContext)
    return

