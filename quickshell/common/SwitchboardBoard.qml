import QtQuick
import "SwitchboardModel.js" as Model

Item {
    id: board
    required property var frame
    required property real clock
    signal injected()
    readonly property var layout: Model.links()
    width: 1200; height: 380
    Repeater {
        model: 5
        Item {
            id: edge
            required property int index
            readonly property var points: Model.ortho(board.layout.nodes[board.layout.chain[index]], board.layout.nodes[board.layout.chain[index+1]])
            SwitchboardPath { path: Model.route(edge.points, 1); stroke: '#506572'; thickness: 1.5 }
            SwitchboardPath { path: Model.route(edge.points, board.frame.edges[edge.index]); stroke: '#b5d9e6'; thickness: 2.5 }
            SwitchboardPath { path: Model.route(edge.points.slice().reverse(), board.frame.enemy[edge.index]); stroke: '#fb4b61'; thickness: 3 }
            SwitchboardPath { path: Model.route(edge.points, board.frame.reclaimed[edge.index]); stroke: '#cdeab8'; thickness: 3 }
            Rectangle {
                readonly property var point: Model.pointOnRoute(edge.points, ((board.frame.t*0.85+edge.index*0.17)%1)*board.frame.edges[edge.index])
                x: point.x-3; y: point.y-3; width: 6; height: 6
                color: board.frame.turned ? '#cbebac' : '#e8c883'
                visible: board.frame.edges[edge.index] > 0.05 && !board.frame.done
            }
        }
    }
    Repeater {
        model: 5
        SwitchboardPath {
            required property int index
            path: Model.route(Model.ortho(board.layout.nodes[board.layout.branches[index][1]], board.layout.nodes[board.layout.branches[index][0]]), 1)
            stroke: '#344751'
        }
    }
    Repeater {
        model: 3
        Item {
            id: tether
            required property int index
            readonly property var worker: board.frame.workers[index]
            readonly property real ax: index === 1 ? worker.x : worker.x + worker.w
            readonly property real hx: ax + (index === 1 ? -12 : 10)
            readonly property var points: [[ax, worker.y+44], [hx, worker.y+44], [hx, worker.target.y], [worker.target.x, worker.target.y]]
            SwitchboardPath {
                path: Model.route(tether.points, tether.worker.connected)
                stroke: tether.worker.dead ? '#69384c' : '#c5a5d2'; dashed: true
            }
            Rectangle {
                readonly property var point: Model.pointOnRoute(tether.points, (board.frame.t*1.4+tether.index*0.2)%1)
                x: point.x-2; y: point.y-2; width: 4; height: 4; color: '#dfc479'
                visible: tether.worker.connected > 0 && !tether.worker.dead && !board.frame.done
            }
            SwitchboardPath {
                path: Model.route(tether.points.slice().reverse(), tether.worker.attacked ? 1-tether.worker.health : 0)
                stroke: '#f5586c'; thickness: 2
            }
        }
    }
    Repeater {
        model: 11
        Item {
            id: station
            required property int index
            readonly property var node: board.frame.nodeStates[index]
            // Centered branch labels must clear the scan outline and tether.
            readonly property var labelOffset: board.layout.labels[node.id] || [0,-46,'middle']
            readonly property color ink: node.owner === 'daemon' ? '#b6d794' : node.owner === 'contested' ? '#edc57d' : '#c1677c'
            x: node.x; y: node.y
            SwitchboardPath {
                path: station.node.id === 'core' ? 'M-18 -12H18V10L0 25L-18 10Z' : station.node.id === 'ice' ? 'M-16 -16H16V16H-16Z' : 'M-7 -7H7V7H-7Z'
                stroke: station.ink; thickness: station.node.kind ? 2 : 1.5; fill: '#11131b'
            }
            Rectangle { x: -3; y: -3; width: 6; height: 6; color: station.ink; opacity: station.node.claim }
            Rectangle {
                anchors.centerIn: parent; width: 28; height: 28; color: 'transparent'
                border.color: station.ink; radius: station.node.id === 'eject' ? 14 : 0
                opacity: station.node.scan > 0 && station.node.scan < 1 ? 0.7 : 0
                rotation: 45
            }
            SwitchboardText {
                x: station.labelOffset[0] - (station.labelOffset[2] === 'end' ? width : station.labelOffset[2] === 'middle' ? width/2 : 0)
                y: station.labelOffset[1]-8
                font.pixelSize: 9; font.letterSpacing: 0.6; color: '#a9bdc8'
                text: station.node.id === 'eject' && board.frame.recovering && board.frame.t >= 9.7 && board.frame.t < 12.7 ? 'BACKDOOR PORT' : station.node.name
            }
            SwitchboardText {
                x: station.labelOffset[0] - (station.labelOffset[2] === 'end' ? width : station.labelOffset[2] === 'middle' ? width/2 : 0)
                y: station.labelOffset[1]+13
                font.pixelSize: 7; color: station.ink; text: station.node.label
            }
        }
    }
    Item {
        x: 680; y: 273
        Rectangle {
            anchors.centerIn: parent
            width: 46 + Math.sin(board.frame.t*10)*6; height: width; radius: width/2
            color: 'transparent'; border.color: '#fa3e60'
            opacity: board.frame.fighting ? (1-board.frame.gateOpen)*0.65 : 0
        }
        SwitchboardPath {
            x: -board.frame.gateOpen*19; y: -board.frame.gateOpen*5
            path: 'M-15 -15H0V15H-15Z'; stroke: '#ef536d'; fill: '#321822'
            opacity: 1-board.frame.gateOpen*0.6
        }
        SwitchboardPath {
            x: board.frame.gateOpen*19; y: board.frame.gateOpen*5
            path: 'M0 -15H15V15H0Z'; stroke: '#ef536d'; fill: '#321822'
            opacity: 1-board.frame.gateOpen*0.6
        }
    }
    SwitchboardPath {
        path: 'M590 12H610V33L600 41L590 33ZM580 9H620V35L600 49L580 35Z'
        stroke: '#c5d693'; thickness: 2; opacity: 0.75
    }
    SwitchboardPath {
        path: 'M470 298H730M600 300V337'; stroke: '#71596b'; dashed: true
    }
    SwitchboardText { x: 265; y: 308; text: 'AUTHENTICATION BOUNDARY'; font.pixelSize: 6; color: '#7b8793' }
    Repeater {
        model: 3
        SwitchboardDaemon {
            required property int index
            worker: board.frame.workers[index]
        }
    }
    SwitchboardPath {
        path: 'M870 344H927V320H944'
        stroke: '#a9caa9'; thickness: 2; dashed: true
        opacity: !board.frame.accepted && board.frame.t >= 7.3 ? 1-board.frame.departure.unplug : 0
    }
    SwitchboardPath {
        path: 'M18 281H8V67H18M263 281H270V374H1194V158H1182'
        stroke: '#c3dca2'; dashed: true
        opacity: board.frame.recovering && board.frame.t >= 10.8 && board.frame.t < 12.6 ? 0.8 : 0
    }
    SwitchboardBreaker { frame: board.frame; clock: board.clock; onInjected: board.injected() }
}
