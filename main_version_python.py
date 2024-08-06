# Importar las bibliotecas necesarias
import pandas as pd
import sqlite3
import matplotlib.pyplot as plt
import seaborn as sns
import plotly.express as px
import re
from unidecode import unidecode

# Definir las rutas a los archivos de datos
path_data1 = "C:/path/a/los/archivos/municipios.xlsx"
path_data2 = "C:/path/a/los/archivos/Prestadores.xlsx"

# Leer los datos de los archivos de Excel
dataset_municipios = pd.read_excel(path_data1)
dataset_prestadores = pd.read_excel(path_data2)

# Mapeo de nombres de ciudades para estandarización
city_name_map = {
    "BOGOTA": "BOGOTA DC",
    "BOGOTÁ": "BOGOTA DC",
    "MEDELLÍN": "MEDELLIN",
    "MEDELLIN": "MEDELLIN",
    "CALI": "CALI",
    "BARRANQUILLA": "BARRANQUILLA",
    "CARTAGENA": "CARTAGENA",
    "SANTA MARTA": "SANTA MARTA",
    "BUCARAMANGA": "BUCARAMANGA"
}

# Función para limpiar y normalizar nombres eliminando caracteres especiales y acentos
def clean_and_normalize(name):
    if pd.notna(name):
        # Eliminar caracteres especiales y puntuación
        cleaned_name = re.sub(r'[^a-zA-Z0-9\s]', '', name)  # Eliminar caracteres no alfanuméricos
        cleaned_name = re.sub(r'\s+', ' ', cleaned_name)  # Reemplazar múltiples espacios con un solo espacio
        cleaned_name = cleaned_name.strip()  # Eliminar espacios en blanco al inicio y al final

        # Eliminar acentos y convertir a mayúsculas
        cleaned_name = unidecode(cleaned_name).upper()

        # Estandarizar nombres comunes de ciudades colombianas
        for original, standardized in city_name_map.items():
            cleaned_name = re.sub(rf'\b{original}\b', standardized, cleaned_name)

        return cleaned_name
    return name

# Limpiar y normalizar nombres en los conjuntos de datos
dataset_municipios['Municipio'] = dataset_municipios['Municipio'].apply(clean_and_normalize)
dataset_municipios['Departamento'] = dataset_municipios['Departamento'].apply(clean_and_normalize)
dataset_prestadores['muni_nombre'] = dataset_prestadores['muni_nombre'].apply(clean_and_normalize)
dataset_prestadores['depa_nombre'] = dataset_prestadores['depa_nombre'].apply(clean_and_normalize)

# Establecer conexión a la base de datos SQLite
conect = sqlite3.connect("C:/Users/USUARIO/OneDrive/Escritorio/proyecto_entrevista_adres/base_adres.db")

# Escribir los conjuntos de datos normalizados en SQLite, sobrescribiendo tablas existentes si es necesario
dataset_municipios.to_sql("tabla_municipios", conect, if_exists='replace', index=False)
dataset_prestadores.to_sql("tabla_prestadores", conect, if_exists='replace', index=False)

# Eliminar la tabla limpia si existe para evitar duplicaciones
conect.execute("DROP TABLE IF EXISTS tabla_municipios_clean;")

# Limpiar y procesar los datos creando una nueva tabla limpia
conect.execute("""
CREATE TABLE tabla_municipios_clean AS
SELECT 
  UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Departamento, '%', ''), '>', ''), 'qU', 'qu'), '&', ''), '  ', ' '), 'D C', 'DC'), '  ', ' '), '  ', ' '), '  ', ' '))) AS Departamento_Limpio,
  UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Municipio, '&', ''), '!', ''), '*', ''), '?', ''), '#', ''), '''', ''), '’', ''), '  ', ' '))) AS Municipio_Limpio,
  Dep, Depmun, Superficie, Poblacion, Irural, Region
FROM 
  tabla_municipios;""")

# Normalizar y ajustar el campo `muni_nombre` en `tabla_prestadores` para asegurar coincidencias correctas
prestadores_clean = pd.read_sql_query("SELECT * FROM tabla_prestadores", conect)
prestadores_clean['muni_nombre'] = prestadores_clean['muni_nombre'].apply(clean_and_normalize)
prestadores_clean.to_sql("tabla_prestadores", conect, if_exists='replace', index=False)

# Realizar la consulta de unión para obtener los datos combinados
query_merged_data = """
  SELECT 
    p.depa_nombre AS Departamento,
    m.Municipio_Limpio AS Municipio,
    m.Region,
    m.Poblacion,
    p.naju_nombre AS Naturaleza_Juridica,
    COUNT(p.codigo_habilitacion) AS Num_Prestadores,
    p.clpr_nombre AS Tipo_Prestador
  FROM 
    tabla_prestadores p
  INNER JOIN 
    tabla_municipios_clean m
  ON 
    p.depa_nombre = m.Departamento_Limpio AND 
    p.muni_nombre = m.Municipio_Limpio
  GROUP BY 
    p.depa_nombre, m.Municipio_Limpio, m.Region, m.Poblacion, p.naju_nombre, p.clpr_nombre
  ORDER BY 
    Num_Prestadores DESC;"""

# Ejecutar la consulta para obtener los datos combinados
merged_data = pd.read_sql_query(query_merged_data, conect)
print("Datos Combinados:")
print(merged_data.head())

# Comprobar la presencia de Bogotá y Medellín en los datos combinados
bogota_check_updated = pd.read_sql_query("SELECT * FROM tabla_municipios_clean WHERE Municipio_Limpio LIKE '%BOGOTA%'", conect)
medellin_check_updated = pd.read_sql_query("SELECT * FROM tabla_municipios_clean WHERE Municipio_Limpio LIKE '%MEDELLIN%'", conect)

print("Bogotá en Municipios Limpios:")
print(bogota_check_updated)
print("Medellín en Municipios Limpios:")
print(medellin_check_updated)

print("Bogotá en Prestadores:")
print(pd.read_sql_query("SELECT * FROM tabla_prestadores WHERE muni_nombre LIKE '%BOGOT%'", conect))

# Calcular la relación prestadores/población
merged_data['Ratio_Prestadores_Poblacion'] = merged_data['Num_Prestadores'] / merged_data['Poblacion']

# Agrupar ciudades según rangos de población
bins = [0, 50000, 500000, 1000000, float('inf')]
labels = ["<50k", "50k-500k", "500k-1M", ">1M"]
merged_data['Population_Group'] = pd.cut(merged_data['Poblacion'], bins=bins, labels=labels, right=False)

# Calcular la distribución de `naju_nombre` por grupo de población
naju_distribution = merged_data.groupby(['Population_Group', 'Naturaleza_Juridica'])['Num_Prestadores'].sum().reset_index()
naju_distribution['Total_Naju'] = naju_distribution.groupby('Population_Group')['Num_Prestadores'].transform('sum')
naju_distribution['Percentage'] = (naju_distribution['Num_Prestadores'] / naju_distribution['Total_Naju']) * 100

# Generar un gráfico de barras apiladas para mostrar la proporción de naturaleza jurídica por grupo de población
plt.figure(figsize=(10, 6))
sns.barplot(data=naju_distribution, x='Population_Group', y='Percentage', hue='Naturaleza_Juridica')
plt.title('Distribución de Naturaleza Jurídica por Grupo de Población')
plt.xlabel('Grupo de Población')
plt.ylabel('Proporción (%)')
plt.legend(title='Naturaleza Jurídica')
plt.show()

# Calcular el porcentaje de cada tipo de prestador dentro de cada grupo de población
prestador_percentage = merged_data.groupby(['Population_Group', 'Tipo_Prestador'])['Num_Prestadores'].sum().reset_index()
prestador_percentage['Total_Prestadores'] = prestador_percentage.groupby('Population_Group')['Num_Prestadores'].transform('sum')
prestador_percentage['Percentage'] = (prestador_percentage['Num_Prestadores'] / prestador_percentage['Total_Prestadores']) * 100

# Generar un gráfico de barras apiladas para mostrar la proporción de tipo de prestador por grupo de población
plt.figure(figsize=(10, 6))
sns.barplot(data=prestador_percentage, x='Population_Group', y='Percentage', hue='Tipo_Prestador')
plt.title('Distribución de Tipos de Prestadores por Grupo de Población')
plt.xlabel('Grupo de Población')
plt.ylabel('Proporción (%)')
plt.legend(title='Tipo de Prestador')
plt.show()

# Generar un gráfico de barras para mostrar la distribución de clase de persona
clase_persona_distribution = dataset_prestadores['clase_persona'].value_counts().reset_index()
clase_persona_distribution.columns = ['clase_persona', 'Count']

plt.figure(figsize=(8, 5))
sns.barplot(data=clase_persona_distribution, x='clase_persona', y='Count', palette='viridis')
plt.title('Distribución de Clase de Persona')
plt.xlabel('Clase de Persona')
plt.ylabel('Cantidad')
plt.show()

# Seleccionar las 5 ciudades más pobladas
top_5_populated_cities = merged_data.nlargest(5, 'Poblacion')

# Seleccionar las 5 ciudades con población menor a 500.000 más pobladas
under_500k_cities = merged_data[merged_data['Poblacion'] < 500000].nlargest(5, 'Poblacion')

# Generar gráficos de dona para las 5 ciudades más pobladas
for city in top_5_populated_cities['Municipio']:
    category_data_query = f"""
    SELECT clpr_nombre, COUNT(*) AS Num_Prestadores
    FROM tabla_prestadores p
    JOIN tabla_municipios_clean m ON p.muni_nombre = m.Municipio_Limpio
    WHERE m.Municipio_Limpio = '{city}'
    GROUP BY clpr_nombre;"""
    category_data = pd.read_sql_query(category_data_query, conect)

    fig = px.pie(category_data, names='clpr_nombre', values='Num_Prestadores', hole=0.4, title=f"Distribución de Tipos de Prestadores en {city} (Más Poblada)")
    fig.show()

# Generar gráficos de dona para las 5 ciudades con población menor a 500.000
for city in under_500k_cities['Municipio']:
    category_data_query = f"""
    SELECT clpr_nombre, COUNT(*) AS Num_Prestadores
    FROM tabla_prestadores p
    JOIN tabla_municipios_clean m ON p.muni_nombre = m.Municipio_Limpio
    WHERE m.Municipio_Limpio = '{city}'
    GROUP BY clpr_nombre;"""
    category_data = pd.read_sql_query(category_data_query, conect)

    fig = px.pie(category_data, names='clpr_nombre', values='Num_Prestadores', hole=0.4, title=f"Distribución de Tipos de Prestadores en {city} (Menor de 500k)")
    fig.show()

# Preparar los datos para el informe
report_data = prestador_percentage.sort_values(['Population_Group', 'Percentage'], ascending=[True, False])
report_data = report_data.groupby('Population_Group').apply(lambda x: ', '.join(f"{row['Tipo_Prestador']} {row['Percentage']:.2f}%" for idx, row in x.iterrows())).reset_index(name='Report')

# Guardar el informe en un archivo de texto
report_text = "Reporte de Porcentaje de Tipos de Prestadores por Grupo de Población:\n" + "\n".join(f"{row['Population_Group']}: {row['Report']}\n" for idx, row in report_data.iterrows())

with open("reporte_tipos_prestadores_por_grupo_poblacion.txt", "w") as file:
    file.write(report_text)

# Imprimir mensaje de confirmación
print("El informe ha sido guardado exitosamente en 'reporte_tipos_prestadores_por_grupo_poblacion.txt'")

# Cerrar la conexión a la base de datos
conect.close()
