import QtQuick 2.0

import Qak 1.0
import Qak.Tools 1.0
import Qak.QtQuick 2.0

import "."

Item {
    id: game

    anchors { fill: parent }

    paused: App.paused || userPaused
    onPausedChanged: { App.debug('Game',paused ? 'paused' : 'continued') }

    property bool userPaused: false

    visible: opacity > 0
    opacity: o(game.parent)
    Behavior on opacity {
        NumberAnimation { duration: 300 }
    }

    function o(p) {
        if(p && 'opacity' in p) {
            if(p.opacity >= 1)
                return 1
        }
        return 0
    }

    property string currentScene: "0"
    property string previousScene: ""
    property Item scene: sceneLoader.item
    property var sceneData
    property var incubator: Incubator.get()
    property var dynamicLoaded: ({})
    property var objectBlacklist: ({})
    property var objectSpawnlist: ({})
    property var staticObjects: ({})

    property string scene2type: "right"

    function getObject(name) {
        if(name in dynamicLoaded)
            return dynamicLoaded[name]

        var found = false
        var fObject
        if(scene && 'canvas' in scene) {
            Aid.loopChildren(scene.canvas,function(object) {
                if(found)
                    return

                if('name' in object && object.name === name) {
                    found = true
                    fObject = object
                }
            })
        }
        return fObject
    }

    function isObjectDynamic(name) {
        return (name in dynamicLoaded)
    }

    function isObjectStatic(name) {
        var found = false
        var fObject
        if(scene && 'canvas' in scene) {
            Aid.loopChildren(scene.canvas,function(object) {
                if(found)
                    return

                if('name' in object && object.name === name) {
                    found = true
                    fObject = object
                }
            })
        }
        return found
    }

    function destroyObject(name) {
        if(name in dynamicLoaded) {
            var o = dynamicLoaded[name]
            o.removeFromInventory()
            o.destroy()
            dynamicLoaded[name] = undefined
        }
    }

    function blacklistObject(name) {
        objectBlacklist[name] = true
    }

    function unblacklistObject(name) {
        objectBlacklist[name] = false
    }

    function isBlacklisted(name) {
        if(name in objectBlacklist) {
            return (objectBlacklist[name] === true)
        }
        return false
    }

    function clearDynamicallyLoaded() {

        var i, o
        for(i in dynamicLoaded) {
            if(dynamicLoaded[i]) {
                o = dynamicLoaded[i]

                if(!isBlacklisted(o.name) && Aid.qtypeof(o) === "Object" && !o.inInventory && ('stateless' in o && !o.stateless)) {
                    var name = o.name
                    objectSpawnlist[name] = name
                }

                o.destroy()
            }
        }
        dynamicLoaded = {}
    }

    property alias inventory: inventory

    readonly property bool canLoadScene: opacity > 0 && store.isLoaded && inventory.isLoaded && sceneLoader.active && sceneLoader.status === Loader.Ready
    onCanLoadSceneChanged: {
        if(canLoadScene) {
            loadScene()
        }
    }

    Component.onCompleted: {
        store.load()
        inventory.load()
    }

    Component.onDestruction: {
        clearDynamicallyLoaded()
        inventory.save()
        store.save()
    }

    signal objectReady(var object)
    signal objectDragged(var object)
    signal objectDropped(var object)
    signal objectCombined(var object, var otherObject)
    signal objectClicked(var object)
    signal objectReturned(var object)
    signal objectTravelingToInventory(var object)
    signal objectAddedToInventory(var object)
    signal objectRemovedFromInventory(var object)

    JSONReader {
        id: jsonReader
    }

    Statistics {
        id: sessionStatistics
    }

    Store {
        id: store
        name: "game"

        property alias currentScene: game.currentScene
        property alias objectBlacklist: game.objectBlacklist
        property alias objectSpawnlist: game.objectSpawnlist
        property alias scene2type: game.scene2type

    }

    Modes {
        id: modes

        Mode {
            name: 'in-game'
            onEnter: sceneLoader.opacity = 1
            onLeave: sceneLoader.opacity = 0
        }

        Mode {
            name: 'pause'
            when: game.paused
            onEnter: onBack(function(){ App.paused = false })
            onLeave: goBack()
        }

    }

    function goToScene(scene) {
        previousScene = currentScene
        clearDynamicallyLoaded()
        sceneLoader.active = false
        sceneLoadTimer.scene = scene
    }

    readonly property bool sceneUnloaded: !sceneLoader.active || !sceneLoader.status === Loader.Ready
    onSceneUnloadedChanged: {
        App.debug('Scene unloaded',currentScene)
    }

    Timer {
        id: sceneLoadTimer
        running: sceneUnloaded
        interval: 500
        repeat: true
        property string scene: ""
        onTriggered: {
            if(scene !== "") {
                game.currentScene = scene
                sceneLoader.active = true
            } else
                stop()
        }
    }

    function loadScene() {
        if(!sceneData)
            sceneData = jsonReader.read(App.getAsset('scenes/scenes.json'))

        var layers = sceneData['layers']
        var tilesets = sceneData['tilesets']

        var i, objects, tiles
        for(i in layers) {
            var layer = layers[i]
            if('type' in layer && layer.type === "objectgroup" && 'name' in layer && layer.name === game.currentScene) {
                objects = layer.objects
                break;
            }
        }
        for(i in tilesets) {
            var tileset = tilesets[i]
            if('name' in tileset && tileset.name === game.currentScene) {
                tiles = tileset.tiles
                break;
            }
        }

        for(i in objects) {
            var object = objects[i]

            if(!('__read' in object)) {

                if('properties' in object) {
                    Aid.extend(object,object.properties)
                    delete object.properties
                    delete object.propertytypes
                }

                if('type' in object) {

                    if(object.type !== "Area") {
                        // NOTE FIX tileset - tiled coordinates are origin Bottom Left
                        object.y = object.y-object.height
                    } else {
                        // NOTE fix areas using tileset images - ah maaan
                        if("tileId" in object) {
                            object.y = object.y-object.height
                        }
                    }

                    if(object.type === "Object") {
                        // NOTE set scene the object is spawned on
                        object.scene = game.currentScene
                    }
                }


                if('combines' in object) {
                    object.keys = JSON.parse(object.combines)
                    delete object.combines
                }

                if("tileId" in object && 'image' in tiles[object.tileId]) {
                    object.itemSource = App.getAsset(tiles[object.tileId].image.replace("../",''))
                    delete object.tileId
                }

                if("ellipse" in object) {
                    delete object.ellipse
                }

                if("sounds" in object && !Aid.isObject(object.sounds)) {
                    var sounds = JSON.parse(object.sounds)
                    for(var tag in sounds) {
                        sounds[tag] = App.getAsset(sounds[tag])
                    }

                    object.sounds = sounds
                }

                if("soundMap" in object && !Aid.isObject(object.soundMap)) {
                    object.soundMap = JSON.parse(object.soundMap)
                }

                if("description" in object && Aid.startsWith(object.description,"[\n")) {
                    object.description = JSON.parse(object.description)
                }

                object.__read = true
            }
        }

        initializeObjects(objects)

        //App.debug(App.serialize(objects))
    }

    function initializeObjects(objects) {

        staticObjects = {}

        var i, fromScene = {}, component
        Aid.loopChildren(scene.canvas,function(object) {
            if('name' in object) {
                if(isBlacklisted(object.name)) {
                    App.debug('Object',object.name,'is blacklisted. Hidding...')
                    object.visible = false
                    return
                }

                staticObjects[object.name] = object
            }
        })

        for(i in objects) {
            var object = objects[i]
            if(object.name in staticObjects) {
                var staticObject = staticObjects[object.name]

                // NOTE Object already has a state saved on disk - skip setting values
                if(Aid.qtypeof(staticObject) === "Object" && staticObject.store.existOnDisk()) {
                    App.debug('Static object',staticObject.name,'already has a state saved on disk. Skipping...')
                    continue
                }

                App.debug('Correcting static object',staticObject.name,'from scene data')
                setProperties(staticObject,object,true)


            } else {
                fromScene[object.name] = true
                spawnObject(object)
            }
        }

        // NOTE go through inventory and spawn any objects from other scenes
        var ic = inventory.contents
        for(i in ic) {
            var object = ic[i]

            if(isBlacklisted(object.name)) {
                App.debug('Object',object.name,'is blacklisted. Skipping...')
                continue
            }

            if(!fromScene[object.name]) {
                var attrs = {
                    'name': object.name,
                }
                if('itemSource' in object)
                    attrs.itemSource = object.itemSource

                component = objectComponent

                App.debug('Spawning dynamic object from INVENTORY',attrs.name)
                incubator.now(component, scene.canvas, attrs, function(o){
                    App.debug('Spawned dynamic INVENTORY object',o.name,o)
                    inventory.add(o)

                    dynamicLoaded[o.name] = o
                })
            }
        }

        // NOTE go through loose objects and spawn
        var os = objectSpawnlist
        for(var name in os) {

            if(isBlacklisted(name)) {
                App.debug('Object',name,'is blacklisted. Skipping...')
                continue
            }

            if(!fromScene[name]) {
                var attrs = {
                    'name': name,
                }

                component = objectComponent

                App.debug('SPAWNED Dynamic object',attrs.name,'prepared')
                incubator.now(component, scene.canvas, attrs, function(o){
                    App.debug('SPAWNED Dynamic object',o.name,o.draggable,o.z)

                    if(o.scene !== currentScene) {
                        App.debug("I'm not currently here. Bye",o.name)
                        o.destroy()
                        return
                    }

                    dynamicLoaded[o.name] = o

                })
            }

        }
    }

    function spawnObject(object,onSpawned) {

        if(isBlacklisted(object.name)) {
            App.debug('Object',object.name,'is blacklisted. Not spawning...')
            return
        }

        if(!('type' in object)) {
            App.warn("No TYPE attribute in",object.name,"Skipping...")
            return
        }

        if(!(object.type === "Object" || object.type === "Area")) {
            App.warn(object.type,"is not a supported OBJECT spawn type",object.name,"Skipping...")
            return
        }

        var attrs = { }
        setProperties(attrs,object)

        var component = objectComponent
        if(object.type === "Area")
            component = areaComponent

        incubator.now(component, scene.canvas, attrs, function(o){
            App.debug('Spawned dynamic object',o.name,o)
            if(inventory.has(o)) {
                inventory.add(o)
            }
            dynamicLoaded[o.name] = o
            if (typeof onSpawned === "function") {
                onSpawned(o)
            }
        })
    }

    function setProperties(to,from,onlySetIfExist) {
        var excludes = ['id','gid','__read','visible']
        for(var p in from) {
            if(excludes.indexOf(p) > -1)
                continue

            if(onlySetIfExist) {
                if(p in to) {
                    to[p] = from[p]
                    //App.debug('Property e',p,'from',from.name)
                }
            } else {
                to[p] = from[p]
                //App.debug('Property',p,'from',from.name)
            }

        }
    }

    Component {
        id: objectComponent
        Object {

        }
    }

    Component {
        id: areaComponent
        Area {

        }
    }

    Loader {
        id: pauseLoader
        anchors { fill: parent }
        source: 'menus/Pause.qml'
        active: opacity > 0

        visible: status == Loader.Ready && opacity > 0

        opacity: game.paused ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }
    }

    Loader {
        id: sceneLoader
        anchors { fill: parent }

        source: 'scenes/'+currentScene+'.qml'

        active: opacity > 0

        visible: status == Loader.Ready && opacity > 0

        opacity: 0
        Behavior on opacity {
            NumberAnimation { duration: 1500 }
        }

    }

    Image {
        anchors {
            right: parent.right
            bottom: parent.bottom
        }
        source: App.getAsset('menu_button.png')
        MouseArea {
            anchors { fill: parent }
            onClicked: userPaused = !userPaused
        }
    }

    Image {
        anchors {
            left: parent.left
            bottom: parent.bottom
        }
        source: App.getAsset('inv_button.png')
        MouseArea {
            anchors { fill: parent }
            onClicked: inventory.show = !inventory.show
        }
        DropSpot {
            anchors { fill: parent }
            keys: [ "inventory" ]
            name: "inventory"
            onDropped: {
                var o = drag.source
                if(o._at === "inventory")
                    return
                drop.accept()
                o.addToInventory()
            }
        }
    }

    Inventory {
        id: inventory

        paused: game.paused

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        property bool show: false
        readonly property bool _show: show && !paused

        on_ShowChanged: core.sounds.play('tick_soft')

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
        }

        states: [
            State {
                name: "shown"; when: inventory._show
                AnchorChanges {
                    target: inventory
                    anchors.top: undefined
                    anchors.bottom: game.bottom
                }
            },
            State {
                name: "hidden"; when: !inventory._show
                AnchorChanges {
                    target: inventory
                    anchors.top: game.bottom
                    anchors.bottom: undefined
                }
            }
        ]

        transitions: Transition {
            from: "hidden"; to: "shown"; reversible: true
            AnchorAnimation { duration: 150 }
        }

    }

    function setText(txt) {
        var wpm = 160
        messages.queue = []
        messages.show = false
        for (var i = 0; i < arguments.length; i++) {
            var wc = arguments[i].split(' ').length;
            messages.queue.push( {
                                    'show': Math.round((wc/wpm)*60*1000),
                                    'msg':arguments[i]
                                });
        }
        messages.show = true
    }

    Image {
        id: messages

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }

        source: App.getAsset('messagebox.png')


        property bool show: false
        readonly property bool _show: show && !game.paused

        property var queue: ([])

        Timer {
            id: autoHideTextTimer
            running: messages.show
            repeat: true
            triggeredOnStart: true
            interval: 3000
            onTriggered: {
                var queue = messages.queue
                if(queue.length > 0) {
                    var o = queue.shift()
                    autoHideTextTimer.interval = o.show
                    messageText.text = o.msg
                } else {
                    messages.show = false
                    messageText.text = ""
                }
            }

        }


        Text {
            id: messageText

            anchors.centerIn: parent

            color: core.colors.yellow
            style: Text.Outline; styleColor: core.colors.black
            font { family: core.fonts.standard.name; }
            font.pixelSize: 40

            onLineLaidOut: {
                messages.height = messageText.height + 20
            }
            /*
            Behavior on scale {
                NumberAnimation { duration: 100 }
            }
            */

        }


        states: [
            State {
                name: "shown"; when: messages._show
                AnchorChanges {
                    target: messages
                    anchors.top: game.top
                    anchors.bottom: undefined
                }
            },
            State {
                name: "hidden"; when: !messages._show
                AnchorChanges {
                    target: messages
                    anchors.top: undefined
                    anchors.bottom: game.top
                }
            }
        ]

        transitions: Transition {
            from: "hidden"; to: "shown"; reversible: true
            AnchorAnimation { duration: 150 }
        }

        MouseArea {
            anchors { fill: parent }
            onClicked: {
                messages.show = false
                messageText.text = ""
                messages.queue = []
            }
        }
    }

    Component {
        id: exitComponent
        Image {
            id: exit
            x: -width; y: -height
            width: 179; height: 173
            source: App.getAsset('exit_button.png')

            property alias delay: exitTimer.interval

            visible: opacity > 0
            opacity: 0
            Behavior on opacity {
                NumberAnimation { duration: 300 }
            }

            onOpacityChanged: {
                if(opacity == 0) {
                    exit.destroy()
                }
            }

            SequentialAnimation {
                running: exit.visible
                loops: Animation.Infinite
                NumberAnimation {
                    target: exit
                    property: "y"
                    to: exit.y - 20
                    duration: 800
                    easing.type: Easing.InOutQuad
                }

                NumberAnimation {
                    target: exit
                    property: "y"
                    to: exit.y + 10
                    duration: 800
                    easing.type: Easing.InOutQuad
                }
            }

            Timer {
                id: exitTimer
                running: exit.visible
                interval: 3000
                onTriggered: exit.opacity = 0
            }

            Component.onDestruction: {
                App.debug('Exit sign is out')
            }
        }
    }

    function showExit(x,y,delay,direction) {

        var attrs = {
            x: x,
            y: y,
            delay: delay,
            opacity: 1
        }

        incubator.now(exitComponent, game, attrs, function(o){

        })

    }

    // Global object combinations
    onObjectCombined: {
        if(object.name === "bucket" && otherObject.name === "bubblegum") {
            combineBucketWithGum(object,otherObject)
        }

        if(object.name === "bubblegum" && otherObject.name === "bucket") {
            combineBucketWithGum(otherObject,object)
        }
    }

    function combineBucketWithGum(bucket,gum) {

        gum.play('generic')

        var object = {
            name: "bucket_patched",
            type: "Object",
            x: bucket.x,
            y: bucket.y,
            z: bucket.z,
            sounds: bucket.sounds,
            soundMap: bucket.soundMap,
            description: "The bucket is patched. No holes!",
            scene: currentScene,
            itemSource: bucket.itemSource,
        }

        var animate = !bucket.inInventory

        blacklistObject(bucket.name)
        blacklistObject(gum.name)
        destroyObject(bucket.name)
        destroyObject(gum.name)

        game.spawnObject(object,function(o){
            if(animate)
                game.inventory.addAnimated(o)
            else
                game.inventory.add(o)
        })

        setText('There we go. A patched bucket!')
    }
}
