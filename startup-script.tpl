#!/usr/bin/env bash
apt update && apt install php mysql-client php-mysql -y
gsutil cp gs://${db_bucket}/employees.sql .

DB_HOST=""
until [[ $DB_HOST != "" ]]
do
    DB_HOST=`gcloud sql instances list | grep RUNN | awk '{print $5}'`
    echo "Waiting sql instance to become available ..."
    sleep 10
done

mysql -h $${DB_HOST} -u${db_user} -p${db_pass} < employees.sql

echo '<?php
header("Content-Type: application/json");
if (isset($_GET["count"]))
{
        $count = $_GET["count"];
}
else
{
        $count = 10;
}

try {
        $db = new PDO("mysql:host=DB_HOST;port=3306;dbname=${db_name};charset=utf8", "${db_user}", "${db_pass}");
        $id = rand(10002,499999);
        $max = 499999-$count;
        $sql = "SELECT * FROM employees ORDER BY RAND() LIMIT $count";
        #$sql = "SELECT * FROM employees WHERE emp_no BETWEEN $id AND $max LIMIT $count";
        if ($statement = $db->prepare($sql)) {
                $statement->execute();
                $rows = $statement->fetchAll(PDO::FETCH_ASSOC);
                $arr = array(
                  "server_ip" => $_SERVER["SERVER_ADDR"],
                  "server_port" => $_SERVER["SERVER_PORT"]
                );
                echo json_encode(array_merge($arr, $rows));
        }
} catch(PDOException $e) {
            echo $e->getMessage();
            return null;
}
?>' > /var/www/html/index.php

sed -i "s/DB_HOST/$${DB_HOST}/g" /var/www/html/index.php