import folium
from folium.plugins import HeatMap, HeatMapWithTime, Draw, MarkerCluster
from flask import Flask, render_template
from turfpy.transformation import intersect, circle
import psycopg2
from turfpy import measurement
from geojson import Point, Feature


app = Flask(__name__)

@app.route('/')
def index():  

    conn = psycopg2.connect("dbname")

    cursor = conn.cursor()

    circles = """SELECT "Object".id, "Object".name, coordinates[0], coordinates[1], (ARRAY[5000, 3000, 1000, 500])["avaliability_id"], "DepartOrg".name, "Availability".name
    FROM "Object" inner join "DepartOrg" on "DepartOrg".id = "Object".deporg_id
    inner join "Availability" on "Object".avaliability_id = "Availability".id
    Where "Object".id < 100300;"""
    m = folium.Map(location=[55.7522, 37.6156], zoom_start=10)
    cursor.execute(circles)
    records = cursor.fetchall()
    manyCircle(m, records, cursor)

    intersected(m, records, cursor)

    information(m, records, cursor)
    m.save('map.html')

    return m._repr_html_()

def colors(count):
    if 76<=count<=1000:
        return "#00ff1a"
    if 55<=count<=76:
        return "#00ff37"
    if 36<=count<=54:
        return "#00ff09"
    if 27<=count<=35:
        return "#3f0"
    if 15<=count<=26:
        return "#9dff00"
    if 10<=count<=14:
        return "#f90"
    if 5<=count<=9:
        return "#ff6a00"
    if 1<=count<=4:
        return "#ff004d"
    if count<=0:
        return "red"
    
def manyCircle(map, records, cursor):
     for record in records:
        counts = f"""select count(DISTINCT "ObjectHasGym".gym_id) from "Object"
            inner join "ObjectHasGym" on "Object".id = "ObjectHasGym".object_id
            inner join "Gym" on "ObjectHasGym".gym_id = "Gym".id
            where "Object".id = {record[0]}"""
        cursor.execute(counts, record[0])
        for count in cursor:
            nubmers = count[0]
        if record[2]:
            if record[3]:
                if record[4]:
                    folium.Circle(location=[record[2], record[3]], stroke=False, fill_opacity=0.2, radius=record[4] ,fill=True,fill_color=colors(nubmers)).add_to(map)


def intersected(map, records, cursor):
    #Закрашивание пересечений
    for row in records:
        centerOne = Feature(geometry=Point((float(row[3]), float(row[2]))))
        circleOne = circle(centerOne, radius = float(row[4])/1000)
        countOne = f"""select count(DISTINCT "ObjectHasGym".gym_id) from "Object"
            inner join "ObjectHasGym" on "Object".id = "ObjectHasGym".object_id
            inner join "Gym" on "ObjectHasGym".gym_id = "Gym".id
            where "Object".id = {row[0]}"""
        cursor.execute(countOne, row[0])
        countsOne = cursor.fetchall()
        for countOne in countsOne:
            nubmerOne = countOne[0]
        for rowTwo in records:
            centerTwo = Feature(geometry=Point((float(rowTwo[3]), float(rowTwo[2]))))
            circleTwo = circle(centerTwo, radius = float(rowTwo[4])/1000)      
            if circleOne != circleTwo:
                if intersect([circleOne, circleTwo]):
                    countTwo = f"""select count(DISTINCT "ObjectHasGym".gym_id) from "Object"
                        inner join "ObjectHasGym" on "Object".id = "ObjectHasGym".object_id
                        inner join "Gym" on "ObjectHasGym".gym_id = "Gym".id
                        Where "Object".id = {rowTwo[0]}"""
                    cursor.execute(countTwo, rowTwo[0])
                    countsTwo = cursor.fetchall()
                    for countTwo in countsTwo:
                        nubmerTwo = countTwo[0]
                    style_function = lambda x: {'fillColor': colors(nubmerOne + nubmerTwo), 'stroke': False}
                    folium.GeoJson(data=intersect([circleOne, circleTwo]), style_function=style_function).add_to(map)


def information(map, records, cursor):
    tooltip = "Click me!"
    for inform in records:
        gym = ""
        types = ""
        views = ""
        sport_zones = f"""select DISTINCT "Gym".name, "GymType".name from "Object"
            inner join "ObjectHasGym" on "Object".id = "ObjectHasGym".object_id
            inner join "Gym" on "ObjectHasGym".gym_id = "Gym".id
            inner join "GymType" on "Gym".type_id = "GymType".id
            where "Object".id = {inform[0]}"""
        cursor.execute(sport_zones, inform[0])
        for row in cursor:
            gym += row[0] + ", "
            types += row[1] + ", "

        sport_types = f"""select DISTINCT "SportType".name from "Object"
            inner join "ObjectHasGym" on "Object".id = "ObjectHasGym".object_id
            inner join "SportType" on "ObjectHasGym".sport_type_id = "SportType".id
            where "Object".id = {inform[0]}"""
        cursor.execute(sport_types, inform[0])
        for row in cursor:
            views += row[0] + ", "

        
        html=f"""
        <h1> {inform[1]}</h1>
        <p>1. {inform[5]}</p>
        <p>2. {gym}</p>
        <p>3. {types}</p>
        <p>4. {views}</p>
        <p>5. {inform[6]}</p>
        """
        iframe = folium.IFrame(html=html, width=300, height=300)
        popup = folium.Popup(iframe, max_width=2650)
        folium.Marker([inform[2], inform[3]], popup=popup, tooltip=tooltip).add_to(map)


if __name__ == "__main__":
    app.run(debug=True)
