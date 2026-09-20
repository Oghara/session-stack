import QtQuick
import QtQuick.Shapes

Shape {
    id: shape
    property string path: ""
    property color stroke: "#82929b"
    property color fill: "transparent"
    property real thickness: 1
    property bool dashed: false
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: shape.stroke
        fillColor: shape.fill
        strokeWidth: shape.thickness
        strokeStyle: shape.dashed ? ShapePath.DashLine : ShapePath.SolidLine
        dashPattern: [4, 3]
        joinStyle: ShapePath.MiterJoin
        PathSvg { path: shape.path }
    }
}
