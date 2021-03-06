QUnit.module 'Batman.Property source tracking'
  setup: ->
    @class = class extends Batman.Object
    @object = new @class

test "calling an accessor from inside an accessor adds a new source", ->
  @class.accessor 'foo', -> @get('bar')
  @object.get('foo')

  deepEqual @object.property('foo').sources.toArray(), [@object.property('bar')]

test "calling accessors with sources adds appropriate sources", ->
  @class.accessor 'foo', -> @get('bar')
  @class.accessor 'bar', -> @get('baz')
  @object.get('foo')

  deepEqual @object.property('foo').sources.toArray(), [@object.property('bar')]
  deepEqual @object.property('bar').sources.toArray(), [@object.property('baz')]

test "calling multiple accessors adds all properties as sources", ->
  @class.accessor 'foo', -> @get('bar'); @get('baz')
  @object.get('foo')

  expected = [@object.property('bar'), @object.property('baz')]
  deepEqual @object.property('foo').sources.toArray(), expected

test "calling mutators from inside an accessor does not add a new source", ->
  @class.accessor 'foo', -> @set('bar', 1234); @unset('baz')
  @object.get('foo')

  deepEqual @object.property('foo').sources.toArray(), []

QUnit.module 'Batman.Property laziness'
  setup: ->
    @class = class extends Batman.Object
    @object = new @class

test "accessing a property with a cached value should not call the accessor", ->
  @class.accessor 'foo', (spy = createSpy())
  @object.property('foo').cached = yes
  @object.property('foo').value = 12345

  equal @object.get('foo'), 12345
  equal spy.callCount, 0

test "observing a property should call the accessor to populate its sources", ->
  @class.accessor 'foo', (spy = createSpy())
  @object.observe 'foo', ->

  equal spy.callCount, 1

test "observing a property should not call the accessor if it has loaded its sources", ->
  @class.accessor 'foo', (spy = createSpy())
  @object.property('foo').sources = new Batman.SimpleSet()
  @object.observe 'foo', ->

  equal spy.callCount, 0

test "observed properties should not call the accessor when cached", ->
  @class.accessor 'foo', (spy = createSpy())
  @object.property('foo').cached = yes
  @object.property('foo').value = 'yup'
  @object.observe 'foo', ->

  equal spy.callCount, 0
  @object.property('foo').fire()
  equal spy.callCount, 0

test "observed properties should call the accessor when changed", ->
  @class.accessor 'foo',
    get: getter = createSpy()
    set: ->
  @object.property('foo').sources = new Batman.SimpleSet()
  @object.observe 'foo', ->

  equal getter.callCount, 0
  @object.set 'foo', 12345
  equal getter.callCount, 1

test "Property.withoutTracking(block) runs the block and returns its return value, while preventing it from registering property sources", ->
  barVal = null
  @class.accessor 'foo', ->
    Batman.Property.withoutTracking =>
      barVal = @get('bar')
  @object.set('bar', 'barVal')

  equal @object.get('foo'), 'barVal'
  equal barVal, 'barVal'

  deepEqual @object.property('foo').sources.toArray(), []


QUnit.module 'Batman.Property',
  setup: ->
    @customKeyAccessor =
      get: createSpy().whichReturns('customKeyValue')
      set: createSpy().whichReturns('customKeyValue')
      unset: createSpy()

    @prototypeKeyAccessor =
      get: createSpy().whichReturns('customKeyValue')
      set: createSpy().whichReturns('customKeyValue')
      unset: createSpy()

    @customBaseAccessor =
      get: createSpy().whichReturns('customBaseValue')

    @prototypeBaseAccessor =
      get: createSpy().whichReturns('customKeyValue')
      set: createSpy().whichReturns('customKeyValue')
      unset: createSpy()

    class TestSubclass  extends Batman.Object
    @base = new TestSubclass
    @base.accessor @customBaseAccessor
    @base.accessor 'foo', @customKeyAccessor
    @base.constructor::accessor @prototypeBaseAccessor
    @base.constructor::accessor 'baz', @prototypeKeyAccessor
    @property = new Batman.Property(@base, 'foo')
    @customBaseAccessorProperty = new Batman.Property(@base, 'bar')

    class ObjectWithNestedAccessors extends Batman.Object
      @accessor 'fromFooAndQux', -> [@get('foo').name(), @get('qux')]
      @accessor 'foo', -> @get('bar')
      @accessor 'bar', -> @get('baz')

    name = ->
      @registerAsMutableSource()
      @_name
    @mutableSomething = $mixin({name: name, _name: 'Jim'}, Batman.EventEmitter)

    @baseWithNestedAccessors = new ObjectWithNestedAccessors
    @baseWithNestedAccessors.set('baz', @mutableSomething)
    @baseWithNestedAccessors.set('qux', "quxVal")

###
# caching
###

test "getValue() stores the value in .value and sets .cached to true", ->
  property = @baseWithNestedAccessors.property('baz')
  strictEqual property.getValue(), @mutableSomething
  strictEqual property.value, @mutableSomething
  strictEqual property.cached, yes

test "getValue() just returns the .value without hitting the accessor if .cached is true", ->
  property = @baseWithNestedAccessors.property('bar')
  spy = spyOn(property.accessor(), 'get')

  property.cached = yes
  property.value = 'cached'
  strictEqual property.getValue(), 'cached'
  ok not spy.called

test "getValue() ignores the cache if its accessor has cache: false", ->
  property = @baseWithNestedAccessors.property('baz') # uses Batman.Property.defaultAccessor, which has caching turned off
  strictEqual property.accessor().cache, false
  strictEqual property.isCachable(), false

  spy = spyOn(property.accessor(), 'get')
  property.cached = yes
  property.value = 'cached'
  strictEqual property.getValue(), @mutableSomething
  ok spy.called

test "refresh() should recursively refresh .value and set .sources to the properties accessed directly by the accessor's getter", ->
  foo = @baseWithNestedAccessors.property('foo')
  bar = @baseWithNestedAccessors.property('bar')
  baz = @baseWithNestedAccessors.property('baz')
  qux = @baseWithNestedAccessors.property('qux')
  fromFooAndQux = @baseWithNestedAccessors.property('fromFooAndQux')
  fromFooAndQux.refresh()

  deepEqual foo.sources.toArray(), [bar]
  deepEqual bar.sources.toArray(), [baz]
  deepEqual baz.sources.toArray(), []
  deepEqual foo.sources.toArray(), [bar]
  deepEqual foo.sources.toArray(), [bar]

  fromFooAndQux = @baseWithNestedAccessors.property('fromFooAndQux')
  qux = @baseWithNestedAccessors.property('qux')
  fromFooAndQux.refresh()
  deepEqual fromFooAndQux.sources.toArray(), [foo, @mutableSomething, qux]

test "if the value of a property with observers fires its 'change' event at some point after the property has refreshed its sources, then the property will refresh its .value and .sources", ->
  foo = @baseWithNestedAccessors.property('foo')
  bar = @baseWithNestedAccessors.property('bar')
  baz = @baseWithNestedAccessors.property('baz')
  qux = @baseWithNestedAccessors.property('qux')
  fromFooAndQux = @baseWithNestedAccessors.property('fromFooAndQux')
  fromFooAndQux.observe ->

  fromFooAndQux.refresh()
  deepEqual fromFooAndQux.sources.toArray(), [foo, @mutableSomething, qux]
  deepEqual fromFooAndQux.value, ['Jim', 'quxVal']

  @mutableSomething._name = 'Wanda'
  @mutableSomething.fire('change')

  deepEqual foo.sources.toArray(), [bar]
  deepEqual bar.sources.toArray(), [baz]
  deepEqual baz.sources.toArray(), []
  deepEqual qux.sources.toArray(), []
  deepEqual fromFooAndQux.sources.toArray(), [foo, @mutableSomething, qux]

  strictEqual foo.value, @mutableSomething
  strictEqual bar.value, @mutableSomething
  strictEqual baz.value, @mutableSomething
  strictEqual qux.value, 'quxVal'
  deepEqual fromFooAndQux.value, ['Wanda', 'quxVal']

test "when a property has no observers and one of its sources changes, the property should merely invalidate its cache instead of refreshing", ->
  base = @baseWithNestedAccessors
  bar = base.property('bar')
  baz = base.property('baz')
  equal bar.getValue(), @mutableSomething
  equal bar.value, @mutableSomething
  equal bar.cached, yes
  baz.setValue('newValue')
  equal bar.value, @mutableSomething
  equal bar.cached, no
  equal bar.getValue(), 'newValue'
  equal bar.value, 'newValue'
  equal bar.cached, yes


###
# isolation
###
test ".isolate() and .expose() use a count to determine if this property will update itself when its sources change", ->
  bar = @baseWithNestedAccessors.property('bar')
  baz = @baseWithNestedAccessors.property('baz')
  bar.observe(observer = createSpy())

  bar.isolate()
  baz.setValue('baz2')
  equal bar.getValue(), @mutableSomething
  equal observer.called, false

  bar.expose()
  equal observer.callCount, 1
  deepEqual observer.lastCallArguments, ['baz2', @mutableSomething, 'bar']
  equal bar.getValue(), 'baz2'

  bar.isolate()
  baz.setValue('baz3')
  equal bar.getValue(), 'baz2'
  equal observer.callCount, 1

  bar.isolate()
  baz.setValue('baz4')
  equal bar.getValue(), 'baz2'
  equal observer.callCount, 1

  bar.expose()
  equal bar.getValue(), 'baz2'
  equal observer.callCount, 1

  bar.expose()
  equal bar.getValue(), 'baz4'
  equal observer.callCount, 2
  deepEqual observer.lastCallArguments, ['baz4', 'baz2', 'bar']

test ".isolate() and .expose() use a count to determine if this property will fire change events when it is set to a new value", ->
  bar = @baseWithNestedAccessors.property('bar')
  baz = @baseWithNestedAccessors.property('baz')
  bar.observe(barObserver = createSpy())
  baz.observe(bazObserver = createSpy())

  baz.isolate()
  baz.setValue('baz2')
  equal baz.getValue(), 'baz2'
  equal bar.getValue(), @mutableSomething
  equal barObserver.called, false
  equal bazObserver.called, false

  baz.expose()
  equal barObserver.callCount, 1
  equal bazObserver.callCount, 1
  deepEqual barObserver.lastCallArguments, ['baz2', @mutableSomething, 'bar']
  deepEqual bazObserver.lastCallArguments, ['baz2', @mutableSomething, 'baz']
  equal baz.getValue(), 'baz2'
  equal bar.getValue(), 'baz2'

  baz.isolate()
  baz.setValue('baz3')
  equal baz.getValue(), 'baz3'
  equal bar.getValue(), 'baz2'
  equal barObserver.callCount, 1
  equal bazObserver.callCount, 1

  baz.isolate()
  baz.setValue('baz4')
  equal baz.getValue(), 'baz4'
  equal bar.getValue(), 'baz2'
  equal barObserver.callCount, 1
  equal bazObserver.callCount, 1

  baz.expose()
  equal baz.getValue(), 'baz4'
  equal bar.getValue(), 'baz2'
  equal barObserver.callCount, 1
  equal bazObserver.callCount, 1

  baz.expose()
  equal baz.getValue(), 'baz4'
  equal bar.getValue(), 'baz4'
  equal barObserver.callCount, 2
  equal bazObserver.callCount, 2
  deepEqual barObserver.lastCallArguments, ['baz4', 'baz2', 'bar']
  deepEqual bazObserver.lastCallArguments, ['baz4', 'baz2', 'baz']

test ".expose() will only trigger a .refresh() if updates have come in from sources while it was isolated", ->
  bar = @baseWithNestedAccessors.property('bar')
  refreshSpy = spyOn(bar, 'refresh')
  bar.isolate()
  bar.expose()
  equal refreshSpy.called, false

###
# accessing
###
test "Property.defaultAccessor does vanilla JS property access", ->
  obj = {}

  equal typeof Batman.Property.defaultAccessor.get.call(obj, 'foo'), 'undefined'
  obj.foo = 'fooVal'
  equal Batman.Property.defaultAccessor.get.call(obj, 'foo'), 'fooVal'

  equal Batman.Property.defaultAccessor.set.call(obj, 'foo', 'newVal'), 'newVal'
  equal obj.foo, 'newVal'

  equal Batman.Property.defaultAccessor.unset.call(obj, 'foo'), 'newVal'
  equal typeof obj.foo, 'undefined'

test "accessor() returns the accessor specified on the base for that key, if present", ->
  equal @property.accessor(), @customKeyAccessor

test "accessor() returns the accessor specified on the base's prototype for that key, if present", ->
  equal new Batman.Property(@base, 'baz').accessor(), @prototypeKeyAccessor

test "accessor() returns the base's default accessor if none is specified for the key", ->
  equal @customBaseAccessorProperty.accessor(), @customBaseAccessor

test "accessor() returns the base's prototype's default accessor if none is specified for key or base instance", ->
  @base._batman.defaultAccessor = null
  equal new Batman.Property(@base, 'bar').accessor(), @prototypeBaseAccessor

test "accessor() returns Property.defaultAccessor if none is specified for key or base", ->
  equal new Batman.Property({}, 'foo').accessor(), Batman.Property.defaultAccessor

test "getValue() calls the accessor's get(key) method in the context of the property's base", ->
  equal @property.getValue(), 'customKeyValue'
  deepEqual @customKeyAccessor.get.lastCallArguments, ['foo']
  equal @customKeyAccessor.get.lastCallContext, @base

test "setValue(val) calls the accessor's set(key, val) method in the context of the property's base", ->
  equal @property.setValue('customKeyValue'), 'customKeyValue'
  deepEqual @customKeyAccessor.set.lastCallArguments, ['foo', 'customKeyValue']
  equal @customKeyAccessor.set.lastCallContext, @base

test "unsetValue() calls the accessor's unset(key) method in the context of the property's base", ->
  equal typeof @property.unsetValue(), 'undefined'
  deepEqual @customKeyAccessor.unset.lastCallArguments, ['foo']
  equal @customKeyAccessor.unset.lastCallContext, @base

test "property() works on non Batman objects", ->
  property = Batman.Property.forBaseAndKey(window, 'Array')
  property.observe spy = createSpy()
  property.fire()
  ok spy.called

  property = Batman.Property.forBaseAndKey({}, 'foo')
  property.observe spy = createSpy()
  property.fire()
  ok spy.called

test "toJSON with null values works correctly", ->
  properties = {prop1: 1, prop2: "foo", prop3: null, prop4: undefined}
  obj = new Batman.Object properties
  deepEqual obj.toJSON(), properties

# #177 (http://jsfiddle.net/zbQMZ/)
test "setValue or unsetValue within a getter should not register the updated property as a source of the accessor's property", ->
  obj = new Batman.Object
  obj.accessor 'foo', ->
    @set('bar', 'baz')
  obj.accessor 'bar', ->
    @unset('baz')
  obj.get('foo')
  obj.get('bar')
  deepEqual obj.property('foo').sources.toArray(), []
  deepEqual obj.property('bar').sources.toArray(), []

QUnit.module 'Batman.Property final properties',
  setup: ->
    @thing = new Batman.Object
    @thing.accessor 'foo',
      get: -> @get('baz')
      final: true
    @thing.accessor 'bar', Batman.mixin({}, Batman.Property.defaultAccessor, final: true)

test "set(key) for a final property locks in the value unless it is undefined", ->
  @thing.set 'bar', undefined
  strictEqual @thing.get('bar'), undefined
  @thing.set 'bar', null
  strictEqual @thing.get('bar'), null
  @thing.set 'bar', 'something else'
  strictEqual @thing.get('bar'), null

test "get(key) for a final property with sources locks in the first defined value", ->
  strictEqual @thing.get('foo'), undefined
  @thing.set('baz', 'something')
  strictEqual @thing.get('foo'), 'something'
  @thing.set('baz', 'something else')
  strictEqual @thing.get('foo'), 'something'

test "observe(key) for a final property with sources calls back with the first defined value", ->
  @thing.observe 'bar', spy = createSpy()
  equal spy.callCount, 0
  @thing.set('bar', 'something')
  equal spy.callCount, 1
  @thing.set('bar', 'something else')
  equal spy.callCount, 1

test "observe(key) for a final property with sources calls back with the first defined value", ->
  @thing.observe 'foo', spy = createSpy()
  equal spy.callCount, 0
  @thing.set('baz', 'something')
  equal spy.callCount, 1
  @thing.set('baz', 'something else')
  equal spy.callCount, 1


QUnit.module 'Batman.Property promises',
  setup: ->
    class @SpecialThing extends Batman.Object
      @accessor
        get: @getter = createSpy(Batman.Property.defaultAccessor.get)
        set: @setter = createSpy(Batman.Property.defaultAccessor.set)
        unset: @unsetter = createSpy(Batman.Property.defaultAccessor.unset)
    @thing = new @SpecialThing

test "passing a promise function to a classAccessor declaration wraps the class's accessor", ->
  @SpecialThing.classAccessor 'classFoo', promise: (deliver) -> deliver("error", "result")
  equal @SpecialThing.get('classFoo'), "result"

test "promises with fetchers which return something return the fetcher's return value synchronously", ->
  @thing.accessor 'foo', promise: (deliver) -> return 1
  equal @thing.get('foo'), 1

test "promises with fetchers which return something and synchronously deliver something return the delivered value", ->
  @thing.accessor 'foo', promise: (deliver) -> deliver(null, 2); return 1
  equal @thing.get('foo'), 2

test "passing a promise function to an accessor declaration wraps the class's default accessor", ->
  @thing.accessor 'foo', promise: (deliver) -> deliver("error", "result")

  equal @SpecialThing.getter.callCount, 0
  equal @SpecialThing.setter.callCount, 0
  equal @SpecialThing.unsetter.callCount, 0

  equal @thing.get('foo'), "result"

  equal @SpecialThing.getter.callCount, 1
  equal @SpecialThing.setter.callCount, 0
  equal @SpecialThing.unsetter.callCount, 0

  equal @thing.get('foo'), "result"

  equal @SpecialThing.getter.callCount, 1
  equal @SpecialThing.setter.callCount, 0
  equal @SpecialThing.unsetter.callCount, 0

test "asynchronous delivery calls the wrapped setter", ->
  deliver = null
  @thing.accessor 'foo', promise: (d) -> deliver = d; return

  equal @thing.get('foo'), undefined

  equal @SpecialThing.getter.callCount, 1
  equal @SpecialThing.setter.callCount, 0
  equal @SpecialThing.unsetter.callCount, 0

  deliver(null, "result")
  equal @thing.get('foo'), "result"

  equal @SpecialThing.getter.callCount, 2
  equal @SpecialThing.setter.callCount, 1
  equal @SpecialThing.unsetter.callCount, 0

test "multiple gets before delivery don't call the fetcher multiple times", ->
  @thing.accessor 'foo', promise: fetcher = createSpy()

  equal @thing.get('foo'), undefined
  equal @thing.get('foo'), undefined
  equal @thing.get('foo'), undefined

  equal fetcher.callCount, 1

test "fetchers which deliver undefined don't retrigger fetch", ->
  @thing.accessor 'foo', promise: fetcher = createSpy()

  equal @thing.get('foo'), undefined

  deliver = fetcher.lastCallArguments[0]
  deliver.call(null, undefined)

  equal @thing.get('foo'), undefined
  equal fetcher.callCount, 1

test "resetting a promise re-fetches the promise", ->
  fetcher = createSpy().whichReturns('foo')

  @thing.accessor 'foo', promise: fetcher
  @thing.get('foo')
  fetcher.lastCallArguments[0].call(null, null, 'bar')
  equal @thing.get('foo'), 'bar'

  @thing._resetPromise('foo')

  @thing.get('foo')

  equal fetcher.callCount, 2

test "resetting a promise makes the next get to it return the return value of the fetcher", ->
  fetcher = createSpy().whichReturns('foo')

  @thing.accessor 'foo', promise: fetcher
  @thing.get('foo')
  fetcher.lastCallArguments[0].call(null, null, 'bar')
  equal @thing.get('foo'), 'bar'

  @thing._resetPromise('foo')

  equal @thing.get('foo'), 'foo'
