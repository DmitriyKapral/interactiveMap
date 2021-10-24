--=================================================================
----------------------------------------------------------------Создание схемы УлУТ
DROP SCHEMA IF EXISTS ulut CASCADE;
CREATE SCHEMA ulut;
----------------------------------------------------------------Создание и наполнение таблицы параметров
DROP TABLE IF EXISTS ulut.parameters;
CREATE TABLE ulut.parameters(
    city_polygon_part_count INTEGER NOT NULL,
	grid_cell_size FLOAT NOT NULL,
	x_min FLOAT NOT NULL,
	x_max FLOAT NOT NULL,
	y_min FLOAT NOT NULL,
	y_max FLOAT NOT NULL
);
INSERT INTO ulut.parameters VALUES (0, 0, 0, 0, 0, 0);
----------------------------------------------------------------Создание таблицы ulut
DROP TABLE IF EXISTS ulut.ulut;
CREATE TABLE ulut.ulut(
	id SERIAL NOT NULL PRIMARY KEY,
	x_crd FLOAT,
	y_crd FLOAT,
	x_ind INTEGER,
	y_ind INTEGER,
	not_blank BOOLEAN,
	a_square GEOMETRY
);
----------------------------------------------------------------Обновление параметров
DROP FUNCTION IF EXISTS update_parameters;
CREATE FUNCTION update_parameters(polygon_part_count INTEGER, grid_size FLOAT, min_x FLOAT, max_x FLOAT, min_y FLOAT, max_y FLOAT)
RETURNS VOID AS 
$$ 
BEGIN	
	UPDATE ulut.parameters 
	SET 
        city_polygon_part_count=polygon_part_count,
		grid_cell_size=grid_size,
		x_min=min_x,
		x_max=max_x,
		y_min=min_y,
		y_max=max_y;
END;  
$$ 
LANGUAGE 'plpgsql';
--SELECT update_parameters(111, 111, 111, 111, 111, 111);
----------------------------------------------------------------Наполнение таблицы ulut
DROP FUNCTION IF EXISTS fill_ulut_table;
CREATE FUNCTION fill_ulut_table(x_crd FLOAT, y_crd FLOAT, x_ind INTEGER, y_ind INTEGER, a_square GEOMETRY)
RETURNS VOID AS 
$$ 	
BEGIN
	INSERT INTO ulut.ulut(x_crd, y_crd, x_ind, y_ind, not_blank, a_square)
	VALUES (x_crd, y_crd, x_ind, y_ind, false, a_square);
END;  
$$ 
LANGUAGE 'plpgsql';
----------------------------------------------------------------Получение количества частей полигона города
DROP FUNCTION IF EXISTS get_city_polygon_part_count;
CREATE FUNCTION get_city_polygon_part_count()
RETURNS INTEGER AS
$$
BEGIN
	RETURN
	(SELECT COUNT(*)
    FROM planet_osm_polygon
    WHERE admin_level='4');
END;  
$$ 
LANGUAGE 'plpgsql';
--SELECT get_city_polygon_part_count();
----------------------------------------------------------------Получение частей полигона города по индексам
DROP FUNCTION IF EXISTS get_city_polygon_part;
CREATE FUNCTION get_city_polygon_part(part_index INTEGER, SRID INTEGER)
RETURNS GEOMETRY AS
$$
DECLARE
    part_count INTEGER:=get_city_polygon_part_count();
BEGIN
    RETURN
    ((SELECT ST_Transform(way, SRID)
        FROM planet_osm_polygon
        WHERE admin_level='4'
        ORDER BY osm_id ASC
        LIMIT part_index + 1)
    EXCEPT
    (SELECT ST_Transform(way, SRID)
        FROM planet_osm_polygon
        WHERE admin_level='4'
        ORDER BY osm_id ASC
        LIMIT part_index));
END;  
$$ 
LANGUAGE 'plpgsql';
--SELECT get_city_polygon_part(0, 3857);
----------------------------------------------------------------Добавление запятой, если это нужно, перед добавлением записи
DROP FUNCTION IF EXISTS add_comma_seporator;
CREATE FUNCTION add_comma_seporator(txt TEXT)
RETURNS TEXT AS 
$$ 	
BEGIN
	IF txt<>'' THEN
		txt:=txt||',';
	END IF;
	RETURN txt;
END;  
$$ 
LANGUAGE 'plpgsql';
--SELECT add_comma_seporator('Hi')
----------------------------------------------------------------Получение границы города
DROP FUNCTION IF EXISTS get_city_polygon;
CREATE FUNCTION get_city_polygon(SRID INTEGER)
RETURNS GEOMETRY AS 
$$
DECLARE
    part_count INTEGER:=get_city_polygon_part_count();
	i INTEGER:=0;
	a_multi_polygon TEXT:='';
	city_multi_polygon GEOMETRY;
BEGIN
	WHILE i < part_count
	LOOP
		a_multi_polygon:=add_comma_seporator(a_multi_polygon);
		a_multi_polygon:=a_multi_polygon||ST_AsText(get_city_polygon_part(i, SRID));
		a_multi_polygon:=REPLACE(a_multi_polygon, 'POLYGON', '');
		i:=i + 1;
	END LOOP;
	city_multi_polygon:=ST_SetSRID(('MULTIPOLYGON('||a_multi_polygon||')')::geometry, SRID);
	return city_multi_polygon;
END;  
$$ 
LANGUAGE 'plpgsql';
--SELECT get_city_polygon(3857);
----------------------------------------------------------------Получение квадратного полигона, служащего в качестве ячейки для сетки
DROP FUNCTION IF EXISTS get_square_grid_cell;
CREATE FUNCTION get_square_grid_cell(x FLOAT, y FLOAT, SRID INTEGER)
RETURNS GEOMETRY AS 
$$
DECLARE
	a_size FLOAT:=(SELECT grid_cell_size FROM ulut.parameters);
BEGIN	
	RETURN ST_MakePolygon(
				ST_MakeLine(
					ARRAY[
						ST_SetSRID(ST_Point(x, y), SRID), 
						ST_SetSRID(ST_Point(x+a_size, y), SRID), 
						ST_SetSRID(ST_Point(x+a_size, y+a_size), SRID),
						ST_SetSRID(ST_Point(x, y+a_size), SRID),
						ST_SetSRID(ST_Point(x, y), SRID)
					]::geometry[]
				)
			);
END;  
$$ 
LANGUAGE 'plpgsql';
--SELECT get_square_grid_cell(0, 0, 3857);
----------------------------------------------------------------Получение сетки
DROP FUNCTION IF EXISTS get_grid;
CREATE FUNCTION get_grid(grid_cell_size FLOAT, SRID INTEGER)
RETURNS VOID AS 
$$ 
DECLARE
    city_polygon_part_count INTEGER:=get_city_polygon_part_count();
    city_polygon GEOMETRY:=get_city_polygon(SRID);
	x_lim FLOAT[]:=ARRAY[ST_XMin(city_polygon), ST_XMax(city_polygon)];
	y_lim FLOAT[]:=ARRAY[ST_YMin(city_polygon), ST_YMax(city_polygon)];
	j FLOAT;
	i FLOAT;
	grid_cell GEOMETRY;
	ulut_params TEXT:='';
BEGIN
	PERFORM update_parameters(city_polygon_part_count, grid_cell_size, x_lim[1], x_lim[2], y_lim[1], y_lim[2]);
	j:=y_lim[1];
	WHILE j<y_lim[2]
	LOOP
		i:=x_lim[1];
		WHILE i<x_lim[2]
		LOOP
			grid_cell:=get_square_grid_cell(i, j, SRID);
			IF ST_Intersects(city_polygon, grid_cell) THEN
				PERFORM 
					fill_ulut_table(
						i::FLOAT,
						j::FLOAT,
						DIV((i-x_lim[1])::numeric, grid_cell_size::numeric)::INTEGER,
						DIV((j-y_lim[1])::numeric, grid_cell_size::numeric)::INTEGER,
						grid_cell
					);
			END IF;
			i:=i+grid_cell_size;
		END LOOP;
		j:=j+grid_cell_size;
	END LOOP;
END;  
$$ 
LANGUAGE 'plpgsql';
SELECT get_grid(250, 3857);
----------------------------------------------------------------Создание  таблицы для импорта
DROP TABLE IF EXISTS ulut.sports_facilities;
CREATE TABLE ulut.sports_facilities(
	id SERIAL NOT NULL PRIMARY KEY,
    sport_facility_id INTEGER NOT NULL,
	sport_facility_name VARCHAR NOT NULL,
	departmental_organization_id INTEGER NOT NULL,
	departmental_organization_name VARCHAR NOT NULL,
	sports_zone_id INTEGER NOT NULL,
	sports_zone_name VARCHAR NOT NULL,
	sports_zone_type VARCHAR NOT NULL,
	sports_zone_availability_value INTEGER NOT NULL,
	sports_zone_availability_name VARCHAR NOT NULL,
	kind_of_sport VARCHAR NOT NULL,
	latitude FLOAT,
	longitude FLOAT,
	a_point GEOMETRY,
	a_circle GEOMETRY
);
----------------------------------------------------------------Изменнение значений под SRID 3857
DROP FUNCTION IF EXISTS update_data;
CREATE FUNCTION update_data(the_id INTEGER, zone_availability_value INTEGER, longit FLOAT, latit FLOAT)
RETURNS VOID AS 
$$
DECLARE
	radius INTEGER:=(ARRAY[5000, 3000, 1000, 500])[zone_availability_value];
	the_point GEOMETRY:=ST_Transform(ST_SetSRID(ST_MakePoint(longit, latit), 4326), 3857);
	x FLOAT:=ST_X(the_point);
	y FLOAT:=ST_Y(the_point);
	the_circle GEOMETRY:=ST_Buffer(the_point, radius, 'quad_segs=64');
BEGIN	
	UPDATE ulut.sports_facilities
	SET
		sports_zone_availability_value=radius,
		a_point=the_point,
		longitude=x,
		latitude=y,
		a_circle=the_circle
	WHERE ulut.sports_facilities.id=the_id;
END;  
$$ 
LANGUAGE 'plpgsql';
SELECT update_data(id, sports_zone_availability_value, longitude, latitude)
FROM ulut.sports_facilities;
----------------------------------------------------------------Количество спортивных зон в клетке, с возможностью разделения по типам
DROP FUNCTION IF EXISTS get_sports_zones_count_in_a_cell;
CREATE FUNCTION get_sports_zones_count_in_a_cell(x_cell FLOAT, y_cell FLOAT, zone_type TEXT, SRID INTEGER)
RETURNS INTEGER AS 
$$
DECLARE
	a_size FLOAT:=(SELECT grid_cell_size FROM ulut.parameters);
BEGIN
	RETURN 	(SELECT
			 	COUNT(DISTINCT sports_facilities_zone_id)			
			FROM
				(SELECT
				 	sports_zone_id AS sports_facilities_zone_id,
					ST_Intersection(
						get_square_grid_cell(x_cell, y_cell, SRID),
						a_circle
					) AS an_intersection
				FROM ulut.sports_facilities
				WHERE
				 	sports_zone_type=zone_type
				 	AND
					ST_Distance(
						ST_SetSRID(ST_MakePoint(x_cell, y_cell), SRID),
						a_circle
					) < 5000 + 1.5*a_size
				) AS q1
			WHERE NOT ST_IsEmpty(an_intersection)
			);
END;  
$$ 
LANGUAGE 'plpgsql';
/*SELECT get_sports_zones_count_in_a_cell(x_crd, y_crd, 'стрелковый тир крытый', 3857) AS cnt
FROM ulut.ulut
LIMIT 100*/
----------------------------------------------------------------Площадь спортивных зон в клетке
DROP FUNCTION IF EXISTS get_sports_zones_area_in_a_cell;
CREATE FUNCTION get_sports_zones_area_in_a_cell(x_cell FLOAT, y_cell FLOAT, SRID INTEGER)
RETURNS FLOAT AS 
$$
DECLARE
	a_size FLOAT:=(SELECT grid_cell_size FROM ulut.parameters);
	area FLOAT;
BEGIN
	area:=  (SELECT 
				ST_Area(
					(SELECT 
						ST_Union(an_intersection)			
					FROM
						(SELECT DISTINCT
							ST_Intersection(
								get_square_grid_cell(x_cell, y_cell, SRID),
								a_circle
							) AS an_intersection
						FROM ulut.sports_facilities
						WHERE
							ST_Distance(
								ST_SetSRID(ST_MakePoint(x_cell, y_cell), SRID),
								a_circle
							) < 5000 + 1.5*a_size
						) AS q1
					WHERE NOT ST_IsEmpty(an_intersection)
					)
				) 
			);
	IF area IS NULL THEN
		area:=0;
	END IF;
	return area;
END;  
$$ 
LANGUAGE 'plpgsql';
/*
SELECT get_sports_zones_area_in_a_cell(x_crd, y_crd, 3857) AS cnt
FROM ulut.ulut
LIMIT 100;
*/
----------------------------------------------------------------Количество видов спортивных услуг в клетке
DROP FUNCTION IF EXISTS get_kind_of_sports_count_in_a_cell;
CREATE FUNCTION get_kind_of_sports_count_in_a_cell(x_cell FLOAT, y_cell FLOAT, SRID INTEGER)
RETURNS INTEGER AS 
$$
DECLARE
	a_size FLOAT:=(SELECT grid_cell_size FROM ulut.parameters);
BEGIN
	RETURN 	(SELECT 
			 	COUNT(DISTINCT sport_kind)			
			FROM
				(SELECT
				 	kind_of_sport AS sport_kind,
					ST_Intersection(
						get_square_grid_cell(x_cell, y_cell, SRID),
						a_circle
					) AS an_intersection
				FROM ulut.sports_facilities
				WHERE
					ST_Distance(
						ST_SetSRID(ST_MakePoint(x_cell, y_cell), SRID),
						a_circle
					) < 5000 + 1.5*a_size
				) AS q1
			WHERE NOT ST_IsEmpty(an_intersection)
			);
END;  
$$ 
LANGUAGE 'plpgsql';
/*SELECT get_kind_of_sports_count_in_a_cell(x_crd, y_crd, 3857) AS cnt
FROM ulut.ulut
LIMIT 100*/
----------------------------------------------------------------Получение ячейки по id
DROP FUNCTION IF EXISTS get_square_grid_cell_by_id;
CREATE FUNCTION get_square_grid_cell_by_id(an_id INTEGER)
RETURNS GEOMETRY AS 
$$
BEGIN	
	RETURN 
	(SELECT a_square
	 FROM ulut.ulut
	 WHERE id=an_id);	
END;  
$$ 
LANGUAGE 'plpgsql';	 
/*SELECT get_square_grid_cell_by_id(id)
FROM ulut.ulut
LIMIT 100*/