"""Prueba rapida de conexion a la base de datos."""

import json
import os

import psycopg2

# Cadena de conexion con los datos reales. Se puede sobrescribir con la
# variable de entorno DATABASE_URL si hiciera falta apuntar a otra base.
URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://neondb_owner:npg_3sDZPUXKon7S@ep-empty-paper-atzhb2iu-pooler.c-9.us-east-1.aws.neon.tech/huellitas_inteligentes?sslmode=require",
)

try:
    conn = psycopg2.connect(URL)
    cur = conn.cursor()
    cur.execute("SELECT fn_dashboard_casa(41)")
    row = cur.fetchone()
    print("JSON:", json.dumps(row[0], indent=2))
except Exception as e:
    print(e)
