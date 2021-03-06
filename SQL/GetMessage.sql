-- Author : Alexandre Ly
-- Date : 01/10/2020
-- Version : 0.5

delimiter //

DROP PROCEDURE IF EXISTS GetMessage//
CREATE PROCEDURE GetMessage(database_name varchar(255), instance_message_id bigint, replay boolean, temp_nb bigint) 
BEGIN

	DECLARE i int unsigned default 0;
    DECLARE j int unsigned default 0;
	DECLARE k int unsigned default 0;

-- 1 Get the message metadata (uevol_message_id, src_id, dst_id and uevol_field list) ------------------------------------------------------------------------------------------------
    
    IF replay = 1 THEN
		SET @instance_message = 'instance_message_replay';
        SET @instance_field = 'instance_field_replay';
	ELSE 
		SET @instance_message = 'instance_message';
        SET @instance_field = 'instance_field';
    END IF;
    
	SET @test_msg_data = CONCAT('
    SELECT id INTO @instance_message_id FROM ', database_name, '.', @instance_message,' 
    WHERE id =', instance_message_id);
	 PREPARE test_msg_data FROM @test_msg_data;
	 EXECUTE test_msg_data;
    
	IF @instance_message_id IS NOT NULL THEN
    
	-- Getting uevol_message_id, src_id and dst_id
	SET @get_msg_data = CONCAT('
    SELECT uevol_message_id, src_id, dst_id INTO @uevol_message_id, @src_id ,@dst_id FROM ', database_name, '.', @instance_message,' 
    WHERE id =', instance_message_id);
	 PREPARE get_msg_data FROM @get_msg_data;
	 EXECUTE get_msg_data;
	
    
		-- Getting the message fields
		SET @get_message_fields = CONCAT( 'SELECT id as uevol_field_id, name,',@src_id,' AS src_id, ',@dst_id,' AS dst_id, type FROM ', database_name, '.uevol_field WHERE uevol_message_id=' , @uevol_message_id);
		-- PREPARE message_fields FROM @message_fields;
		-- EXECUTE message_fields;
		
		SET @message_fields = CONCAT('data_center.message_fields_',temp_nb);
        
		SET @drop_message_fields = CONCAT('DROP TABLE IF EXISTS ', @message_fields ); 
		PREPARE drop_message_fields FROM @drop_message_fields;
		EXECUTE drop_message_fields;
        
		SET @create_message_fields = CONCAT('CREATE TABLE ',@message_fields,' SELECT * FROM(',@get_message_fields,') ga');
		PREPARE create_message_fields FROM @create_message_fields;
		EXECUTE create_message_fields;


	-- 2 Get the snapshots, filter them to keep the message fields and concatenate them ---------------------------------------------------------------------------------------------------


		SET @snapshots = CONCAT(database_name,'.snapshots');

		-- Getting nearest snapshot names
		SET @get_snap_min_name = CONCAT(
		'SELECT name, start_instance_message_id INTO @snap_min_name, @snap_min_start FROM ',@snapshots, ' 
			WHERE start_instance_message_id = (
			SELECT max(start_instance_message_id)
			FROM ', @snapshots, ' 
			WHERE start_instance_message_id <= ', instance_message_id, ')' );
		PREPARE get_snap_min_name FROM @get_snap_min_name;
		EXECUTE get_snap_min_name;
        
        SET @snap_max_name = @snap_min_name;
        
        IF instance_message_id = 0 THEN
				SET @get_snap_max_name = CONCAT('SELECT name INTO @snap_max_name FROM ', @snapshots, ' 
				WHERE start_instance_message_id = (
				SELECT min(start_instance_message_id)
				FROM ', @snapshots, ' 
				WHERE start_instance_message_id > ',instance_message_id,')');
        ELSE
			SET @get_snap_max_name = CONCAT('SELECT name INTO @snap_max_name FROM ', @snapshots, ' 
				WHERE start_instance_message_id = (
				SELECT min(start_instance_message_id)
				FROM ', @snapshots, ' 
				WHERE start_instance_message_id >= ',instance_message_id,')');
        END IF;    
			PREPARE get_snap_max_name FROM @get_snap_max_name;
			EXECUTE get_snap_max_name;

		-- Getting the nearest napshots
		SET @snap_min = CONCAT(database_name,'.',@snap_min_name);
		SET @snap_max = CONCAT(database_name,'.',@snap_max_name);
        

		-- Getting the nearest napshots and filtering by arguments
		SET @get_min = CONCAT('
			SELECT min.uevol_field_id, min.src_id, min.dst_id, min.instance_message_id, min.json_value 
			FROM ',@snap_min,' min 
			INNER JOIN  ',@message_fields,' mf 
			ON min.uevol_field_id = mf.uevol_field_id 
			WHERE min.src_id = ',@src_id,' AND min.dst_id = ',@dst_id);
		  -- PREPARE get_min FROM @get_min;
		  -- EXECUTE get_min;

		SET @snap_min = CONCAT('data_center.snap_min_',temp_nb);
        
		SET @drop_snap_min = CONCAT('DROP TABLE IF EXISTS ', @snap_min ); 
		PREPARE drop_snap_min FROM @drop_snap_min;
		EXECUTE drop_snap_min;
        
		SET @create_snap_min = CONCAT('CREATE TABLE ',@snap_min,' SELECT * FROM(',@get_min,') ga');
		PREPARE create_snap_min FROM @create_snap_min;
		EXECUTE create_snap_min;

	IF @snap_min_name != @snap_max_name THEN
                
		SET @get_max = CONCAT('	
			SELECT max.uevol_field_id, max.src_id, max.dst_id, max.instance_message_id, max.json_value 
			FROM ',@snap_max,' max
			INNER JOIN ',@message_fields,' mf 
			ON max.uevol_field_id = mf.uevol_field_id 
			WHERE max.src_id = ',@src_id,' AND max.dst_id = ',@dst_id);
		-- PREPARE get_max FROM @get_max;
		-- EXECUTE get_max;

		-- Getting the concatenation of both snapshots
		SET @get_all = CONCAT('SELECT * FROM ',@snap_min,' UNION ALL ',@get_max);
		-- PREPARE get_all FROM @get_all;
		-- EXECUTE get_all;
		
		-- Creating a table to store it 
		SET @conc_snap = CONCAT('data_center.conc_snap_',temp_nb);
        
		SET @drop_conc_snap = CONCAT('DROP TABLE IF EXISTS ', @conc_snap ); 
		PREPARE drop_conc_snap FROM @drop_conc_snap;
		EXECUTE drop_conc_snap;
        
		SET @create_conc_snap = CONCAT('CREATE TABLE ',@conc_snap,' SELECT * FROM(',@get_all,') ga');
		PREPARE create_conc_snap FROM @create_conc_snap;
		EXECUTE create_conc_snap;
		

	-- 3 Get the fields which didn't change between snapshots -----------------------------------------------------------------------------------------------------------------------------

		-- Getting the value of fields which didn't change between snapshots by counting
			-- if in the concatenated table the field value/instance__message_id appears twice it means no update
			SET @compare_same = CONCAT(
			'SELECT *
			FROM ', @conc_snap,'  
			GROUP BY uevol_field_id, src_id, dst_id, instance_message_id
			HAVING COUNT(*) > 1 '); 
			-- PREPARE compare_same FROM @compare_same;
			-- EXECUTE compare_same;
			
			SET @same = CONCAT('data_center.same_',temp_nb);
			
			SET @drop_same = CONCAT('DROP TABLE IF EXISTS ', @same ); 
			PREPARE drop_same FROM @drop_same;
			EXECUTE drop_same;
			
			SET @create_same = CONCAT('CREATE TABLE ',@same,' SELECT * FROM(',@compare_same,') ga');
			PREPARE create_same FROM @create_same;
			EXECUTE create_same;

		-- 4 Get the fields which are different between the 2 snapshots------------------------------------------------------------------------------------------------------------------------
			
			-- Getting the value of fields which changed between snapshots by counting
			-- if in the concatenated table the field value/instance__message_id appears only once it means there was an update
			SET @compare_diff = CONCAT('
			SELECT *
			FROM ',@conc_snap,' t 
			GROUP BY uevol_field_id, src_id, dst_id, instance_message_id
			HAVING COUNT(*) =1 
			ORDER BY uevol_field_id'); 
			-- PREPARE compare_diff FROM @compare_diff;
			-- EXECUTE compare_diff;

			SET @instance_field_reduced = CONCAT('
				SELECT uevol_field_id, src_id, dst_id, instance_message_id, relative_path, value 
				FROM ',@instance_field,'  
				WHERE instance_message_id BETWEEN ', @snap_min_start, ' 
					AND ', instance_message_id, ' 
                    AND uevol_message_id = ',@uevol_message_id,'
					AND src_id=',@src_id,' 
					AND dst_id = ',@dst_id );
			-- PREPARE instance_field_reduced FROM @instance_field_reduced;
			-- EXECUTE instance_field_reduced;
		 
			SET @get_diff_update_prem = CONCAT('SELECT in_fr.uevol_field_id,in_fr.src_id, in_fr.dst_id, in_fr.instance_message_id, in_fr.relative_path, in_fr.value
				FROM  (',@instance_field_reduced,') in_fr 
				INNER JOIN (',@compare_diff,') cd 
				ON in_fr.uevol_field_id = cd.uevol_field_id');

			SET @diff_update_prem = CONCAT('data_center.diff_update_prem_',temp_nb);
			
			SET @drop_diff_update_prem = CONCAT('DROP TABLE IF EXISTS ', @diff_update_prem ); 
			PREPARE drop_diff_update_prem FROM @drop_diff_update_prem;
			EXECUTE drop_diff_update_prem;
			
			SET @create_diff_update_prem = CONCAT('CREATE TABLE ',@diff_update_prem,' SELECT * FROM(',@get_diff_update_prem,') gdup');
			PREPARE create_diff_update_prem FROM @create_diff_update_prem;
			EXECUTE create_diff_update_prem;
		 
			-- Accessing instance_field_replay to get the updates for the given fields
			SET @get_diff_recent_update = CONCAT('SELECT prem1.uevol_field_id,prem1.src_id, prem1.dst_id, prem1.instance_message_id, prem1.relative_path, prem2.value
			FROM (
				SELECT uevol_field_id,src_id, dst_id, max(instance_message_id) as instance_message_id, relative_path
				FROM ',@diff_update_prem,' 
				GROUP BY uevol_field_id, relative_path) prem1
			RIGHT OUTER JOIN  ',@diff_update_prem,' prem2
			ON prem1.uevol_field_id=prem2.uevol_field_id 
				AND prem1.instance_message_id = prem2.instance_message_id 
				AND prem1.relative_path = prem2.relative_path
			WHERE prem1.uevol_field_id IS NOT NULL');
			-- PREPARE get_diff_recent_update FROM @get_diff_recent_update;
			-- EXECUTE get_diff_recent_update;
			
			SET @diff_update_rec = CONCAT('data_center.diff_update_rec_',temp_nb);
			
			SET @drop_diff_update_rec = CONCAT('DROP TABLE IF EXISTS ', @diff_update_rec ); 
			PREPARE drop_diff_update_rec FROM @drop_diff_update_rec;
			EXECUTE drop_diff_update_rec;
			
			SET @create_diff_update_rec = CONCAT('CREATE TABLE ',@diff_update_rec,' SELECT * FROM(',@get_diff_recent_update,') ga');
			PREPARE create_diff_update_rec FROM @create_diff_update_rec;
			EXECUTE create_diff_update_rec;
			
			-- Joining with Uevol_field to get field names and keep the last update
			SET @get_diff = CONCAT('SELECT DISTINCT upd.uevol_field_id, upd.src_id, upd.dst_id , mf.name, upd.instance_message_id, upd.relative_path, mf.type, upd.value
			FROM ',@diff_update_rec,' upd 
			INNER JOIN ',@message_fields,' mf
			ON upd.uevol_field_id = mf.uevol_field_id 
			ORDER BY uevol_field_id, relative_path');
			PREPARE get_diff FROM @get_diff;
			-- EXECUTE get_diff;
			 
			SET @diff = CONCAT('data_center.diff_',temp_nb);
			
			SET @drop_diff = CONCAT('DROP TABLE IF EXISTS ', @diff ); 
			PREPARE drop_diff FROM @drop_diff;
			EXECUTE drop_diff;
			
			SET @create_diff = CONCAT('CREATE TABLE ',@diff,' SELECT * FROM(',@get_diff,') ga');
			PREPARE create_diff FROM @create_diff;
			EXECUTE create_diff;
			                       
            IF instance_message_id > (SELECT start_instance_message_id FROM snapshots LIMIT 1,1) THEN

				SET @get_nb_fields_diff = CONCAT('SELECT COUNT( DISTINCT uevol_field_id) INTO @nb_fields_diff FROM ',@diff);
				PREPARE get_nb_fields_diff FROM @get_nb_fields_diff;
				EXECUTE get_nb_fields_diff;
			
				WHILE i<@nb_fields_diff
				DO
				
					SET @get_current_uevol_field_id = CONCAT('SELECT uevol_field_id, src_id, dst_id, name, type INTO @current_uevol_field_id, @current_src_id, @current_dst_id, @current_name, @current_type FROM ',@diff,' LIMIT ',i,',1');
					PREPARE get_current_uevol_field_id FROM @get_current_uevol_field_id;
					EXECUTE get_current_uevol_field_id;
					-- SELECT @current_uevol_field_id;
					
					SET @get_json_value =CONCAT(' SELECT json_value INTO @jv FROM ',@snap_min,' WHERE uevol_field_id = ',@current_uevol_field_id,' AND src_id =',@current_src_id,' AND dst_id = ',@current_dst_id);
					PREPARE get_json_value FROM @get_json_value;
					EXECUTE get_json_value;
					-- SELECT @jv;
					
					SET @get_json_degree = CONCAT('CALL GetJsonDegree(\'',@jv ,'\')');
					PREPARE get_json_degree FROM @get_json_degree;
					EXECUTE get_json_degree;
					-- SELECT @degree;
					
					IF @degree = 1 THEN

						SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
						PREPARE get_keys FROM @get_keys;
						EXECUTE get_keys;
					
						SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
						PREPARE get_json_length FROM @get_json_length;
						EXECUTE get_json_length;
						-- SELECT @length;
					
						SET j =0;
						WHILE j < @length 
						DO
							SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
							PREPARE get_current_key from @get_current_key;
							EXECUTE get_current_key;
								
							SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, \'',@current_name,'\' AS name, instance_message_id, ',@current_key,' as relative_path, ',@current_type,' AS type, JSON_EXTRACT(json_value,\'$.',@current_key,'\')+0 as value
							FROM ',@snap_min,' WHERE uevol_field_id =',@current_uevol_field_id,' AND src_id =',@current_src_id,' AND dst_id = ',@current_dst_id);
							-- SELECT @get_current_rel_path_val;
								
							SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@diff,' (',@get_current_rel_path_val,')');
							PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
							EXECUTE insert_current_rel_path_val;

							SET j = j+1;
					END WHILE;
				END IF;
					
				IF @degree =2 THEN 
				
					SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
					PREPARE get_keys FROM @get_keys;
					EXECUTE get_keys;
					
					SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
					PREPARE get_json_length FROM @get_json_length;
					EXECUTE get_json_length;
					-- SELECT @length;
				
					SET j =0;
					WHILE j < @length 
					DO
						SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
						PREPARE get_current_key from @get_current_key;
						EXECUTE get_current_key;
						-- SELECT @current_key;
						
						SET @get_json_value2 =CONCAT(' SELECT JSON_EXTRACT(\'',@jv,'\',\'$.',@current_key,'\') INTO @jv2');
						PREPARE get_json_value2 FROM @get_json_value2;
						EXECUTE get_json_value2;
						-- SELECT @jv2;

						SET @get_keys2 = CONCAT( 'SELECT JSON_KEYS(\'',@jv2,'\') INTO @keys2');
						PREPARE get_keys2 FROM @get_keys2;
						EXECUTE get_keys2;
                        
						SET @get_json_length2 = CONCAT('SELECT JSON_LENGTH(\'',@jv2,'\') INTO @length2');
						PREPARE get_json_length2 FROM @get_json_length2;
						EXECUTE get_json_length2;
						-- SELECT @length2;
						
						SET k =0;
						WHILE k < @length2 
							DO
							SET @get_current_key2 = CONCAT('SELECT JSON_EXTRACT(\'',@keys2,'\',\'$[',k,']\') INTO @current_key2') ;
							PREPARE get_current_key2 from @get_current_key2;
							EXECUTE get_current_key2;
							-- SELECT @current_key2;
							
							SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, \'',@current_name,'\' AS name, instance_message_id, ',@current_key,' as relative_path, ',@current_type,' AS type,JSON_EXTRACT(json_value,\'$.',@current_key,'.',@current_key2,'\')+0 as value
							FROM ',@snap_min,' WHERE uevol_field_id =',@current_uevol_field_id,' AND src_id =',@current_src_id,' AND dst_id = ',@current_dst_id);
							-- SELECT @get_current_rel_path_val;
							
							SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@diff,' (',@get_current_rel_path_val,')');
							PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
							EXECUTE insert_current_rel_path_val;
								
								SET k=k+1;
							END WHILE;
							
							SET j = j+1;
						END WHILE;
					END IF;
					SET i=i+1;
				 END WHILE; 
			END IF;

		 -- 5 Get the fields which are different between snapshots but have no update preceding the message in between the snapshots---------------------------------------------------------------
			-- Get all other fields
			Set @known_fields = CONCAT('
			SELECT uevol_field_id, src_id, dst_id, instance_message_id FROM ',@same, ' 
			UNION ALL
			SELECT uevol_field_id,src_id, dst_id, instance_message_id FROM ',@diff 
			);
			-- PREPARE known_fields FROM @known_fields;
			-- EXECUTE known_fields;
			
			-- Getting the fields which changed between snapshots but have yet to be updated at the time
			-- We join the result of finding the updates and the fields which changed and see which were not found 
			SET @get_no_update_yet = CONCAT('
			SELECT mf.uevol_field_id , mf.src_id, mf.dst_id
			FROM ',@message_fields,' mf
			LEFT OUTER JOIN (',@known_fields,') kf
			ON mf.uevol_field_id=kf.uevol_field_id 
			WHERE kf.instance_message_id IS NULL');
			-- PREPARE no_update_yet FROM @no_update_yet;
			-- EXECUTE no_update_yet;
			
		SET @compare_no_update_yet = CONCAT(
			'SELECT nuy.uevol_field_id, nuy.src_id, nuy.dst_id, gm.instance_message_id, gm.json_value 
			FROM (',@get_no_update_yet , ') nuy 
			LEFT OUTER JOIN ',@snap_min,' gm
			ON nuy.uevol_field_id=gm.uevol_field_id'); 
			-- PREPARE compare_no_update_yet FROM @compare_no_update_yet;
			-- EXECUTE compare_no_update_yet;
			
			SET @no_update_yet = CONCAT('data_center.no_update_yet_',temp_nb);
			
			SET @drop_no_update_yet = CONCAT('DROP TABLE IF EXISTS ', @no_update_yet ); 
			PREPARE drop_no_update_yet FROM @drop_no_update_yet;
			EXECUTE drop_no_update_yet;
			
			SET @create_no_update_yet = CONCAT('CREATE TABLE ',@no_update_yet,' SELECT * FROM(',@compare_no_update_yet,') ga');
			PREPARE create_no_update_yet FROM @create_no_update_yet;
			EXECUTE create_no_update_yet;

		-- 6 Concatenating no update yet and same -----------------------------------------------------------------------------------------------------------------------------------------------------------
				
			-- We concatenate the fields which stayed the same and those which have yet to be updated
		-- We concatenate the fields which stayed the same and those which have yet to be updated
			SET @get_unchanged_st = CONCAT( 'SELECT * FROM ',@same,' UNION ALL SELECT * FROM ',@no_update_yet);
			-- PREPARE unchanged FROM @get_unchanged_st;
		  
			SET @unchanged_st = CONCAT('data_center.unchanged_st_',temp_nb);

			SET @drop_unchanged_st = CONCAT('DROP TABLE IF EXISTS ', @unchanged_st );
			PREPARE drop_unchanged_st FROM @drop_unchanged_st;
			EXECUTE drop_unchanged_st;

			SET @create_unchanged_st = CONCAT('CREATE TABLE ',@unchanged_st,' SELECT * FROM (',@get_unchanged_st,') gu');
			PREPARE create_unchanged_st FROM @create_unchanged_st;
			EXECUTE create_unchanged_st;
			
				-- Extract json values to concatenate
			SET @get_unchanged_prem = CONCAT('
				SELECT mf.uevol_field_id, mf.src_id, mf.dst_id, name, instance_message_id, mf.type, json_value 
				FROM ',@unchanged_st,' gu
				JOIN ',@message_fields,' mf
				WHERE mf.uevol_field_id = gu.uevol_field_id ');
			-- PREPARE get_unchanged_prem FROM @get_unchanged_prem;
			-- EXECUTE get_unchanged_prem;
			
			SET @unchanged_prem = CONCAT('data_center.unchanged_prem_',temp_nb);
			
			SET @drop_unchanged_prem = CONCAT('DROP TABLE IF EXISTS ', @unchanged_prem ); 
			PREPARE drop_unchanged_prem FROM @drop_unchanged_prem;
			EXECUTE drop_unchanged_prem;
			
			SET @create_unchanged_prem = CONCAT('CREATE TABLE ',@unchanged_prem,' SELECT * FROM(',@get_unchanged_prem,') ga');
			PREPARE create_unchanged_prem FROM @create_unchanged_prem;
			EXECUTE create_unchanged_prem;

			SET @update_unchanged_prem = CONCAT('UPDATE ',@unchanged_prem,' SET instance_message_id = -1, json_value = \'{"000":-1}\' WHERE instance_message_id IS NULL OR json_value = \'{}\'');
			PREPARE update_unchanged_prem FROM @update_unchanged_prem;
			EXECUTE update_unchanged_prem;

			SET @get_nb_fields_unchanged = CONCAT('
				SELECT COUNT(uevol_field_id) INTO @nb_fields_unchanged
				FROM ',@unchanged_prem);
			PREPARE get_nb_fields_unchanged FROM @get_nb_fields_unchanged;
			EXECUTE get_nb_fields_unchanged;
			
			SET @unchanged = CONCAT('data_center.unchanged_',temp_nb);
			
			SET @drop_unchanged = CONCAT('DROP TABLE IF EXISTS ', @unchanged ); 
			PREPARE drop_unchanged FROM @drop_unchanged;
			EXECUTE drop_unchanged;
			
			SET @create_unchanged = CONCAT('CREATE TABLE ',@unchanged,' (
			  `uevol_field_id` int(11) DEFAULT NULL,
			  `src_id` int(11) DEFAULT NULL,
			  `dst_id` int(11) DEFAULT NULL,
			  `name` text,
			  `instance_message_id` bigint(20),
			  `relative_path` text,
			  `type` int(11),
			  `value` double(17,0) DEFAULT NULL
			) ENGINE=InnoDB DEFAULT CHARSET=utf8');
			PREPARE create_unchanged FROM @create_unchanged;
			EXECUTE create_unchanged;

		SET i=0;
		WHILE i<@nb_fields_unchanged
		DO
			
			SET @get_current_data = CONCAT('SELECT json_value INTO @jv FROM ',@unchanged_prem,' LIMIT ',i,',1');
			PREPARE get_current_data FROM @get_current_data;
			EXECUTE get_current_data;
			-- SELECT @get_current_data;
			
			SET @get_json_degree = CONCAT('CALL GetJsonDegree(\'',@jv ,'\')');
			PREPARE get_json_degree FROM @get_json_degree;
			EXECUTE get_json_degree;
			-- SELECT @degree;

			IF @degree = 1 THEN
            
				SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
				PREPARE get_keys FROM @get_keys;
				EXECUTE get_keys;
				
				SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
				PREPARE get_json_length FROM @get_json_length;
				EXECUTE get_json_length;
				-- SELECT @length;
			
				SET j =0;
				WHILE j < @length 
				DO
					SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
					PREPARE get_current_key FROM @get_current_key;
					EXECUTE get_current_key;
						
					SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, name, instance_message_id, ',@current_key,' as relative_path, type, JSON_EXTRACT(json_value,\'$.',@current_key,'\')+0 as value
					FROM ',@unchanged_prem,'  LIMIT ',i,',1');
								
					SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@unchanged,' (',@get_current_rel_path_val,')');
					PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
					EXECUTE insert_current_rel_path_val;

					SET j = j+1;
				END WHILE;
			END IF;
			
			IF @degree =2 THEN 
            
				SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
				PREPARE get_keys FROM @get_keys;
				EXECUTE get_keys;
                
				SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
				PREPARE get_json_length FROM @get_json_length;
				EXECUTE get_json_length;
				-- SELECT @length;
            
				SET j =0;
				WHILE j < @length 
				DO
					SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
					PREPARE get_current_key from @get_current_key;
					EXECUTE get_current_key;
					-- SELECT @current_key;
					
					SET @get_json_value2 =CONCAT(' SELECT JSON_EXTRACT(\'',@jv,'\',\'$.',@current_key,'\') INTO @jv2');
					PREPARE get_json_value2 FROM @get_json_value2;
					EXECUTE get_json_value2;
					-- SELECT @jv2;
					
					SET @get_keys2 = CONCAT( 'SELECT JSON_KEYS(\'',@jv2,'\') INTO @keys2');
					PREPARE get_keys2 from @get_keys2;
					EXECUTE get_keys2;
					-- SELECT @keys2;
                    
					SET @get_json_length2 = CONCAT('SELECT JSON_LENGTH(\'',@jv2,'\') INTO @length2');
					PREPARE get_json_length2 FROM @get_json_length2;
					EXECUTE get_json_length2;
					-- SELECT @length2;
					
					SET k =0;
					WHILE k < @length2 
						DO
                        
						SET @get_current_key2 = CONCAT('SELECT JSON_EXTRACT(\'',@keys2,'\',\'$[',k,']\') INTO @current_key2') ;
						PREPARE get_current_key2 from @get_current_key2;
						EXECUTE get_current_key2;
						-- SELECT @current_key2;
						
						SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, name, instance_message_id, ',@current_key2,' as relative_path, type ,JSON_EXTRACT(json_value,\'$.',@current_key,'.',@current_key2,'\')+0 as value
						FROM ',@unchanged_prem,' LIMIT ',i,',1');
						-- SELECT @get_current_rel_path_val;
						
						SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@unchanged,' (',@get_current_rel_path_val,')');
						PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
						EXECUTE insert_current_rel_path_val;
						
						SET k=k+1;
					END WHILE;
					
					SET j = j+1;
				END WHILE;
			END IF;
			SET i=i+1;
		END WHILE;

        SET @test_null = CONCAT('SELECT count(uevol_field_id) INTO @count_unchanged FROM ',@unchanged);
        PREPARE test_null FROM @test_null;
        EXECUTE test_null;

        IF @count_unchanged = 0 THEN
			SET @get_simple_values = CONCAT('SELECT up.uevol_field_id, up.src_id, up.dst_id, up.name, up.instance_message_id, \'000\' as relative_path, up.type, JSON_EXTRACT(up.json_value,\'$."000"\')+0 as value
			FROM ',@unchanged_prem,' up
			');
			-- PREPARE get_simple_values FROM @get_simple_values;
			-- EXECUTE get_simple_values;
        ELSE
			SET @get_simple_values = CONCAT('SELECT up.uevol_field_id, up.src_id, up.dst_id, up.name, up.instance_message_id, \'000\' as relative_path, up.type, JSON_EXTRACT(up.json_value,\'$."000"\')+0 as value
			FROM ',@unchanged_prem,' up
			LEFT OUTER JOIN ',@unchanged,' u
			ON up.uevol_field_id = u.uevol_field_id AND up.src_id = u.src_id AND up.dst_id = u.dst_id
            WHERE u.name IS NULL
			');
        -- PREPARE get_simple_values FROM @get_simple_values;
        -- EXECUTE get_simple_values;
        END IF;

		SET @insert_simple_values = CONCAT('INSERT INTO ',@unchanged,' (',@get_simple_values,')');
		PREPARE insert_simple_values FROM @insert_simple_values;
		EXECUTE insert_simple_values;
			
		-- 7 Executing the queries -----------------------------------------------------------------------------------------------------------------------------------------------------------
		   
			-- We concatenate everything 
			SET @get_everything = CONCAT( 'SELECT * FROM ',@unchanged,' UNION ALL (SELECT * FROM ',@diff,' GROUP BY uevol_field_id, relative_path)ORDER BY uevol_field_id, relative_path');
			PREPARE get_everything FROM @get_everything;
			EXECUTE get_everything;
            
			EXECUTE drop_message_fields; 
			EXECUTE drop_snap_min; 
			EXECUTE drop_conc_snap;
			EXECUTE drop_same;
			EXECUTE drop_diff_update_prem;
			EXECUTE drop_diff_update_rec;
			EXECUTE drop_diff;
			EXECUTE drop_no_update_yet;
			EXECUTE drop_unchanged_st;
			EXECUTE drop_unchanged_prem;
			EXECUTE drop_unchanged;
-- -----------------------------------------------------------------------------------------------------------------------------------------------------
		ELSE

			SET @get_instance_field_reduced = CONCAT('
			SELECT uevol_field_id, src_id, dst_id, instance_message_id, relative_path, value 
			FROM ',@instance_field,'  
			WHERE instance_message_id BETWEEN ', @snap_min_start,' 
				AND ', instance_message_id, ' 
                AND uevol_message_id = ',@uevol_message_id,' 
				AND src_id =',@src_id,' 
				AND dst_id = ',@dst_id );
			-- PREPARE instance_field_reduced FROM @instance_field_reduced;
			-- EXECUTE instance_field_reduced;
            
			SET @instance_field_reduced = CONCAT('data_center.instance_field_reduced_',temp_nb);
            
			SET @drop_instance_field_reduced = CONCAT('DROP TABLE IF EXISTS ', @instance_field_reduced ); 
			PREPARE drop_instance_field_reduced FROM @drop_instance_field_reduced;
			EXECUTE drop_instance_field_reduced;
			
			SET @create_instance_field_reduced = CONCAT('CREATE TABLE ',@instance_field_reduced,' ',@get_instance_field_reduced);
			PREPARE create_instance_field_reduced FROM @create_instance_field_reduced;
			EXECUTE create_instance_field_reduced;
		 			
			-- Accessing instance_field_replay to get the updates for the given fields
			SET @get_diff_recent_update = CONCAT('SELECT prem1.uevol_field_id,prem1.src_id, prem1.dst_id, prem1.instance_message_id, prem1.relative_path, prem2.value
			FROM (
				SELECT uevol_field_id,src_id, dst_id, max(instance_message_id) as instance_message_id, relative_path
				FROM ',@instance_field_reduced,' 
				GROUP BY uevol_field_id, relative_path) prem1
			RIGHT OUTER JOIN  ',@instance_field_reduced,' prem2
			ON prem1.uevol_field_id=prem2.uevol_field_id 
				AND prem1.instance_message_id = prem2.instance_message_id 
				AND prem1.relative_path = prem2.relative_path
			WHERE prem1.uevol_field_id IS NOT NULL');
			-- PREPARE get_diff_recent_update FROM @get_diff_recent_update;
			-- EXECUTE get_diff_recent_update;

			SET @diff_update_rec = CONCAT('data_center.diff_update_rec_',temp_nb);
			
			SET @drop_diff_update_rec = CONCAT('DROP TABLE IF EXISTS ', @diff_update_rec ); 
			PREPARE drop_diff_update_rec FROM @drop_diff_update_rec;
			EXECUTE drop_diff_update_rec;

			SET @create_diff_update_rec = CONCAT('CREATE TABLE ',@diff_update_rec,' ',@get_diff_recent_update);
			PREPARE create_diff_update_rec FROM @create_diff_update_rec;
			EXECUTE create_diff_update_rec;
			
			-- Joining with Uevol_field to get field names and keep the last update
			SET @get_diff = CONCAT('SELECT DISTINCT upd.uevol_field_id, upd.src_id, upd.dst_id , mf.name, upd.instance_message_id, upd.relative_path, mf.type, upd.value
			FROM ',@diff_update_rec,' upd 
			INNER JOIN ',@message_fields,' mf
			ON upd.uevol_field_id = mf.uevol_field_id 
			ORDER BY uevol_field_id, relative_path');
			PREPARE get_diff FROM @get_diff;
			-- EXECUTE get_diff;
            
			SET @diff= CONCAT('data_center.diff_',temp_nb);
            
			SET @drop_diff = CONCAT('DROP TABLE IF EXISTS ', @diff ); 
			PREPARE drop_diff FROM @drop_diff;
			EXECUTE drop_diff;

			SET @create_diff= CONCAT('CREATE TABLE ',@diff,' ',@get_diff);
			PREPARE create_diff FROM @create_diff;
			EXECUTE create_diff;

			IF instance_message_id > (SELECT start_instance_message_id FROM snapshots LIMIT 1,1) THEN
 
				SET @get_nb_fields_diff = CONCAT('SELECT COUNT( DISTINCT uevol_field_id) INTO @nb_fields_diff FROM ',@diff);
				PREPARE get_nb_fields_diff FROM @get_nb_fields_diff;
				EXECUTE get_nb_fields_diff;
			
				WHILE i<@nb_fields_diff
				DO
				
					SET @get_current_uevol_field_id = CONCAT('SELECT uevol_field_id, src_id, dst_id, name, type INTO @current_uevol_field_id, @current_src_id, @current_dst_id, @current_name, @current_type FROM ',@diff,' LIMIT ',i,',1');
					PREPARE get_current_uevol_field_id FROM @get_current_uevol_field_id;
					EXECUTE get_current_uevol_field_id;
					-- SELECT @current_uevol_field_id;
					
					SET @get_json_value =CONCAT(' SELECT json_value INTO @jv FROM ',@snap_min,' WHERE uevol_field_id = ',@current_uevol_field_id,' AND src_id =',@current_src_id,' AND dst_id = ',@current_dst_id);
					PREPARE get_json_value FROM @get_json_value;
					EXECUTE get_json_value;
					-- SELECT @jv;
					
					SET @get_json_degree = CONCAT('CALL GetJsonDegree(\'',@jv ,'\')');
					PREPARE get_json_degree FROM @get_json_degree;
					EXECUTE get_json_degree;
					-- SELECT @degree;
				
					IF @degree = 1 THEN

						SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
						PREPARE get_keys FROM @get_keys;
						EXECUTE get_keys;
					
						SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
						PREPARE get_json_length FROM @get_json_length;
						EXECUTE get_json_length;
						-- SELECT @length;
					
						SET j =0;
						WHILE j < @length 
						DO
							SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
							PREPARE get_current_key from @get_current_key;
							EXECUTE get_current_key;
								
							SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, \'',@current_name,'\' AS name, instance_message_id, ',@current_key,' as relative_path, ',@current_type,' AS type, JSON_EXTRACT(json_value,\'$.',@current_key,'\')+0 as value
							FROM ',@snap_min,' WHERE uevol_field_id =',@current_uevol_field_id,' AND src_id =',@current_src_id,' AND dst_id = ',@current_dst_id);
							-- SELECT @get_current_rel_path_val;
								
							SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@diff,' (',@get_current_rel_path_val,')');
							PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
							EXECUTE insert_current_rel_path_val;

							SET j = j+1;
						END WHILE;
					END IF;
					
				IF @degree =2 THEN 
				
					SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
					PREPARE get_keys FROM @get_keys;
					EXECUTE get_keys;
					
					SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
					PREPARE get_json_length FROM @get_json_length;
					EXECUTE get_json_length;
					-- SELECT @length;
				
					SET j =0;
					WHILE j < @length 
					DO
						SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
						PREPARE get_current_key from @get_current_key;
						EXECUTE get_current_key;
						-- SELECT @current_key;
						
						SET @get_json_value2 =CONCAT(' SELECT JSON_EXTRACT(\'',@jv,'\',\'$.',@current_key,'\') INTO @jv2');
						PREPARE get_json_value2 FROM @get_json_value2;
						EXECUTE get_json_value2;
						-- SELECT @jv2;
						
						SET @get_keys2 = CONCAT( 'SELECT JSON_KEYS(\'',@jv2,'\') INTO @keys2');
						PREPARE get_keys2 FROM @get_keys2;
						EXECUTE get_keys2;
                        
						SET @get_json_length2 = CONCAT('SELECT JSON_LENGTH(\'',@jv2,'\') INTO @length2');
						PREPARE get_json_length2 FROM @get_json_length2;
						EXECUTE get_json_length2;
						-- SELECT @length2;
						
						SET k =0;
						WHILE k < @length2 
							DO
							SET @get_current_key2 = CONCAT('SELECT JSON_EXTRACT(\'',@keys2,'\',\'$[',k,']\') INTO @current_key2') ;
							PREPARE get_current_key2 from @get_current_key2;
							EXECUTE get_current_key2;
							-- SELECT @current_key2;
							
							SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, \'',@current_name,'\' AS name, instance_message_id, ',@current_key,' as relative_path, ',@current_type,' AS type,JSON_EXTRACT(json_value,\'$.',@current_key,'.',@current_key2,'\')+0 as value
							FROM ',@snap_min,' WHERE uevol_field_id =',@current_uevol_field_id,' AND src_id =',@current_src_id,' AND dst_id = ',@current_dst_id);
							-- SELECT @get_current_rel_path_val;
							
							SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@diff,' (',@get_current_rel_path_val,')');
							PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
							EXECUTE insert_current_rel_path_val;
								
								SET k=k+1;
							END WHILE;
							
							SET j = j+1;
						END WHILE;
					END IF;
					SET i=i+1;
				 END WHILE; 
			END IF;  
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------            
            
			-- Getting the fields which changed between snapshots but have yet to be updated at the time
			-- We join the result of finding the updates and the fields which changed and see which were not found 
			SET @get_no_update_yet = CONCAT('
			SELECT mf.uevol_field_id , mf.src_id, mf.dst_id, mf.name, mf.type
			FROM ',@message_fields,' mf
			LEFT OUTER JOIN ',@diff,' kf
			ON mf.uevol_field_id=kf.uevol_field_id 
			WHERE kf.instance_message_id IS NULL');
			-- PREPARE no_update_yet FROM @no_update_yet;
			-- EXECUTE no_update_yet;
			
			SET @compare_no_update_yet = CONCAT(
			'SELECT nuy.uevol_field_id, nuy.src_id, nuy.dst_id, nuy.name, gm.instance_message_id, nuy.type, gm.json_value 
			FROM (',@get_no_update_yet , ') nuy 
			JOIN ',@snap_min,' gm
			ON nuy.uevol_field_id=gm.uevol_field_id '); 
			-- PREPARE compare_no_update_yet FROM @compare_no_update_yet;
			-- EXECUTE compare_no_update_yet;
			
			SET @no_update_yet = CONCAT('data_center.no_update_yet_',temp_nb);
			
			SET @drop_no_update_yet = CONCAT('DROP TABLE IF EXISTS ', @no_update_yet ); 
			PREPARE drop_no_update_yet FROM @drop_no_update_yet;
			EXECUTE drop_no_update_yet;
			
			SET @create_no_update_yet = CONCAT('CREATE TABLE ',@no_update_yet,' SELECT * FROM(',@compare_no_update_yet,') ga');
			PREPARE create_no_update_yet FROM @create_no_update_yet;
			EXECUTE create_no_update_yet;
			
            SET @get_nb_fields_unchanged = CONCAT('
				SELECT COUNT( uevol_field_id) INTO @nb_fields_unchanged
				FROM ',@no_update_yet);
			PREPARE get_nb_fields_unchanged FROM @get_nb_fields_unchanged;
			EXECUTE get_nb_fields_unchanged;

			SET @unchanged = CONCAT('data_center.unchanged_',temp_nb);
			
			SET @drop_unchanged = CONCAT('DROP TABLE IF EXISTS ', @unchanged ); 
			PREPARE drop_unchanged FROM @drop_unchanged;
			EXECUTE drop_unchanged;
			
			SET @create_unchanged = CONCAT('CREATE TABLE ',@unchanged,' (
			  `uevol_field_id` int(11) DEFAULT NULL,
			  `src_id` int(11) DEFAULT NULL,
			  `dst_id` int(11) DEFAULT NULL,
			  `name` text,
			  `instance_message_id` bigint(20),
			  `relative_path` text,
			  `type` int(11),
			  `value` double(17,0) DEFAULT NULL
			) ENGINE=InnoDB DEFAULT CHARSET=utf8');
			PREPARE create_unchanged FROM @create_unchanged;
			EXECUTE create_unchanged;
			

            SET i = 0;
			WHILE i<@nb_fields_unchanged
			DO
            
			SET @get_current_data = CONCAT('SELECT json_value INTO @jv FROM ',@no_update_yet,' LIMIT ',i,',1');
			PREPARE get_current_data FROM @get_current_data;
			EXECUTE get_current_data;
			-- SELECT @get_current_data;
			
			SET @get_json_degree = CONCAT('CALL GetJsonDegree(\'',@jv ,'\')');
			PREPARE get_json_degree FROM @get_json_degree;
			EXECUTE get_json_degree;

			IF @degree = 1 THEN
            
				SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
				PREPARE get_keys FROM @get_keys;
				EXECUTE get_keys;
            
				SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
				PREPARE get_json_length FROM @get_json_length;
				EXECUTE get_json_length;
				-- SELECT @length;
            
				SET j =0;
				WHILE j < @length 
				DO
					SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
					PREPARE get_current_key from @get_current_key;
					EXECUTE get_current_key;
						
					SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, name, instance_message_id, ',@current_key,' as relative_path, type, JSON_EXTRACT(json_value,\'$.',@current_key,'\')+0 as value
					FROM ',@no_update_yet,' LIMIT ',i,',1');
								
					SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@unchanged,' (',@get_current_rel_path_val,')');
					PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
					EXECUTE insert_current_rel_path_val;

					SET j = j+1;
				END WHILE;
			END IF;
			
			IF @degree =2 THEN 
            
				SET @get_keys = CONCAT( 'SELECT JSON_KEYS(\'',@jv,'\') INTO @keys');
				PREPARE get_keys FROM @get_keys;
				EXECUTE get_keys;
                
				SET @get_json_length = CONCAT('SELECT JSON_LENGTH(\'',@jv,'\') INTO @length');
				PREPARE get_json_length FROM @get_json_length;
				EXECUTE get_json_length;
				-- SELECT @length;
            
				SET j =0;
				WHILE j < @length 
				DO
					SET @get_current_key = CONCAT('SELECT JSON_EXTRACT(\'',@keys,'\',\'$[',j,']\') INTO @current_key') ;
					PREPARE get_current_key from @get_current_key;
					EXECUTE get_current_key;
					-- SELECT @current_key;
					
					SET @get_json_value2 =CONCAT(' SELECT JSON_EXTRACT(\'',@jv,'\',\'$.',@current_key,'\') INTO @jv2');
					PREPARE get_json_value2 FROM @get_json_value2;
					EXECUTE get_json_value2;
					-- SELECT @jv2;
					
					SET @get_keys2 = CONCAT( 'SELECT JSON_KEYS(\'',@jv2,'\') INTO @keys2');
					PREPARE get_keys2 from @get_keys2;
					EXECUTE get_keys2;
					-- SELECT @keys2;
                    
					SET @get_json_length2 = CONCAT('SELECT JSON_LENGTH(\'',@jv2,'\') INTO @length2');
					PREPARE get_json_length2 FROM @get_json_length2;
					EXECUTE get_json_length2;
					-- SELECT @length2;
					
					SET k =0;
					WHILE k < @length2 
						DO
						SET @get_current_key2 = CONCAT('SELECT JSON_EXTRACT(\'',@keys2,'\',\'$[',k,']\') INTO @current_key2') ;
						PREPARE get_current_key2 from @get_current_key2;
						EXECUTE get_current_key2;
						-- SELECT @current_key2;
						
						SET @get_current_rel_path_val = CONCAT('SELECT uevol_field_id, src_id, dst_id, name, instance_message_id, ',@current_key2,' as relative_path, type ,JSON_EXTRACT(json_value,\'$.',@current_key,'.',@current_key2,'\')+0 as value
						FROM ',@no_update_yet,' LIMIT ',i,',1');
						-- SELECT @get_current_rel_path_val;
						
						SET @insert_current_rel_path_val = CONCAT('INSERT INTO ',@unchanged,' (',@get_current_rel_path_val,')');
						PREPARE insert_current_rel_path_val FROM @insert_current_rel_path_val;
						EXECUTE insert_current_rel_path_val;
						
						SET k=k+1;
					END WHILE;
					
					SET j = j+1;
				END WHILE;
			END IF;
			SET i=i+1;
            END WHILE;
            
		SET @test_null = CONCAT('SELECT count(uevol_field_id) INTO @count_unchanged FROM ',@unchanged);
        PREPARE test_null FROM @test_null;
        EXECUTE test_null;
        -- select @count_unchanged;
        
        IF @count_unchanged = 0 THEN
			SET @get_simple_values = CONCAT('SELECT up.uevol_field_id, up.src_id, up.dst_id, up.name, up.instance_message_id, \'000\' as relative_path, up.type, JSON_EXTRACT(up.json_value,\'$."000"\')+0 as value
			FROM ',@no_update_yet,' up
			');
			-- PREPARE get_simple_values FROM @get_simple_values;
			-- EXECUTE get_simple_values;
        ELSE
			SET @get_simple_values = CONCAT('SELECT up.uevol_field_id, up.src_id, up.dst_id, up.name, up.instance_message_id, \'000\' as relative_path, up.type, JSON_EXTRACT(up.json_value,\'$."000"\')+0 as value
			FROM ',@no_update_yet,' up
			LEFT OUTER JOIN ',@unchanged,' u
			ON up.uevol_field_id = u.uevol_field_id AND up.src_id = u.src_id AND up.dst_id = u.dst_id
            WHERE u.name IS NULL 
			');
			 -- PREPARE get_simple_values FROM @get_simple_values;
			 -- EXECUTE get_simple_values;
        END IF;

		SET @insert_simple_values = CONCAT('INSERT INTO ',@unchanged,' (',@get_simple_values,')');
		PREPARE insert_simple_values FROM @insert_simple_values;
		EXECUTE insert_simple_values;
        
		SET @update_unchanged = CONCAT('UPDATE ',@unchanged,' SET value = -1 WHERE instance_message_id = -1 AND value IS NULL');
		PREPARE update_unchanged FROM @update_unchanged;
		EXECUTE update_unchanged;
            
			-- We concatenate everything 
			SET @get_everything = CONCAT( 'SELECT * FROM ',@unchanged,' UNION ALL SELECT * FROM ',@diff,' GROUP BY uevol_field_id, relative_path ORDER BY uevol_field_id, relative_path');
			PREPARE get_everything FROM @get_everything;
			EXECUTE get_everything;
                        
			EXECUTE drop_message_fields; 
			EXECUTE drop_snap_min; 
			EXECUTE drop_diff_update_rec;
			EXECUTE drop_diff;
            EXECUTE drop_instance_field_reduced; 
			EXECUTE drop_no_update_yet;
			EXECUTE drop_unchanged;

		END IF;
        
	ELSE 
		SET @uevol_message_id = NULL;
		SET @src_id =NULL;
		SET @dst_id = NULL;
	END IF;
    
END //

delimiter ;