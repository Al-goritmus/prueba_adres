# Cargar las bibliotecas necesarias
library(readxl)
library(DBI)
library(RSQLite)
library(ggplot2)
library(dplyr)
library(tidyr)
library(gdata)
library(plotly)
library(stringi)

# Definir las rutas a los archivos de datos
path_data1 <- "C:/Users/USUARIO/OneDrive/Escritorio/proyecto_entrevista_adres/data/Municipios.xlsx"
path_data2 <- "C:/Users/USUARIO/OneDrive/Escritorio/proyecto_entrevista_adres/data/Prestadores.xlsx"

# Leer los datos de los archivos de Excel
dataset_municipios <- read_excel(path_data1)
dataset_prestadores <- read_excel(path_data2)

# Mapeo de nombres de ciudades para estandarización
city_name_map <- list(
  "BOGOTA" = "BOGOTA DC",
  "BOGOTÁ" = "BOGOTA DC",
  "MEDELLÍN" = "MEDELLIN",
  "MEDELLIN" = "MEDELLIN",
  "CALI" = "CALI",
  "BARRANQUILLA" = "BARRANQUILLA",
  "CARTAGENA" = "CARTAGENA",
  "SANTA MARTA" = "SANTA MARTA",
  "BUCARAMANGA" = "BUCARAMANGA"
)

# Función para limpiar y normalizar nombres eliminando caracteres especiales y acentos
clean_and_normalize <- function(name) {
  if (!is.na(name)) {
    # Eliminar caracteres especiales y puntuación
    cleaned_name <- gsub("[^[:alnum:][:space:]]", "", name)  # Eliminar caracteres no alfanuméricos
    cleaned_name <- gsub("\\s+", " ", cleaned_name)  # Reemplazar múltiples espacios con un solo espacio
    cleaned_name <- trimws(cleaned_name)  # Eliminar espacios en blanco al inicio y al final
    
    # Eliminar acentos y convertir a mayúsculas
    cleaned_name <- toupper(stri_trans_general(cleaned_name, id = "Latin-ASCII"))
    
    # Estandarizar nombres comunes de ciudades colombianas
    for (original in names(city_name_map)) {
      standardized <- city_name_map[[original]]
      cleaned_name <- gsub(paste0("\\b", original, "\\b"), standardized, cleaned_name)
    }
    
    return(cleaned_name)
  }
  return(name)
}

# Limpiar y normalizar nombres en los conjuntos de datos
dataset_municipios$Municipio <- sapply(dataset_municipios$Municipio, clean_and_normalize)
dataset_municipios$Departamento <- sapply(dataset_municipios$Departamento, clean_and_normalize)
dataset_prestadores$muni_nombre <- sapply(dataset_prestadores$muni_nombre, clean_and_normalize)
dataset_prestadores$depa_nombre <- sapply(dataset_prestadores$depa_nombre, clean_and_normalize)

# Establecer conexión a la base de datos SQLite
conect <- dbConnect(RSQLite::SQLite(), dbname="C:/Users/USUARIO/OneDrive/Escritorio/proyecto_entrevista_adres/base_adres.db")

# Escribir los conjuntos de datos normalizados en SQLite, sobrescribiendo tablas existentes si es necesario
dbWriteTable(conect, "tabla_municipios", dataset_municipios, overwrite=TRUE)
dbWriteTable(conect, "tabla_prestadores", dataset_prestadores, overwrite=TRUE)

# Eliminar la tabla limpia si existe para evitar duplicaciones
dbExecute(conect, "DROP TABLE IF EXISTS tabla_municipios_clean;")

# Limpiar y procesar los datos creando una nueva tabla limpia
dbExecute(conect, "
CREATE TABLE tabla_municipios_clean AS
SELECT 
  UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Departamento, '%', ''), '>', ''), 'qU', 'qu'), '&', ''), '  ', ' '), 'D C', 'DC'), '  ', ' '), '  ', ' '), '  ', ' '))) AS Departamento_Limpio,
  UPPER(TRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Municipio, '&', ''), '!', ''), '*', ''), '?', ''), '#', ''), '''', ''), '’', ''), '  ', ' '))) AS Municipio_Limpio,
  Dep, Depmun, Superficie, Poblacion, Irural, Region
FROM 
  tabla_municipios;")

# Normalizar y ajustar el campo `muni_nombre` en `tabla_prestadores` para asegurar coincidencias correctas
prestadores_clean <- dbGetQuery(conect, "SELECT * FROM tabla_prestadores")
prestadores_clean$muni_nombre <- sapply(prestadores_clean$muni_nombre, clean_and_normalize)
dbWriteTable(conect, "tabla_prestadores", prestadores_clean, overwrite=TRUE)

# Realizar la consulta de unión para obtener los datos combinados
query_merged_data <- "
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
    Num_Prestadores DESC;"

# Ejecutar la consulta para obtener los datos combinados
merged_data <- dbGetQuery(conect, query_merged_data)
print("Datos Combinados:")
print(head(merged_data))

# Comprobar la presencia de Bogotá y Medellín en los datos combinados
bogota_check_updated <- dbGetQuery(conect, "SELECT * FROM tabla_municipios_clean WHERE Municipio_Limpio LIKE '%BOGOTA%'")
medellin_check_updated <- dbGetQuery(conect, "SELECT * FROM tabla_municipios_clean WHERE Municipio_Limpio LIKE '%MEDELLIN%'")

print("Bogotá en Municipios Limpios:")
print(bogota_check_updated)
print("Medellín en Municipios Limpios:")
print(medellin_check_updated)

print("Bogotá en Prestadores:")
print(dbGetQuery(conect, "SELECT * FROM tabla_prestadores WHERE muni_nombre LIKE '%BOGOT%'"))

# Calcular la relación prestadores/población
merged_data <- merged_data %>%
  mutate(Ratio_Prestadores_Poblacion = Num_Prestadores / Poblacion)

# Agrupar ciudades según rangos de población
merged_data$Population_Group <- cut(
  merged_data$Poblacion,
  breaks = c(0, 50000, 500000, 1000000, Inf),
  labels = c("<50k", "50k-500k", "500k-1M", ">1M"),
  right = FALSE
)

# Calcular la distribución de `naju_nombre` por grupo de población
naju_distribution <- merged_data %>%
  group_by(Population_Group, Naturaleza_Juridica) %>%
  summarise(Num_Prestadores = sum(Num_Prestadores), .groups = 'drop') %>%
  group_by(Population_Group) %>%
  mutate(Total_Naju = sum(Num_Prestadores)) %>%
  mutate(Percentage = (Num_Prestadores / Total_Naju) * 100)

# Generar un gráfico de barras apiladas para mostrar la proporción de naturaleza jurídica por grupo de población
ggplot(naju_distribution, aes(x = Population_Group, y = Percentage, fill = Naturaleza_Juridica)) +
  geom_bar(stat = "identity", position = "fill") +
  theme_minimal() +
  labs(title = "Distribución de Naturaleza Jurídica por Grupo de Población",
       x = "Grupo de Población",
       y = "Proporción (%)",
       fill = "Naturaleza Jurídica") +
  scale_y_continuous(labels = scales::percent_format())  # Formato de porcentaje en el eje y

# Calcular el porcentaje de cada tipo de prestador dentro de cada grupo de población
prestador_percentage <- merged_data %>%
  group_by(Population_Group, Tipo_Prestador) %>%
  summarise(Num_Prestadores = sum(Num_Prestadores), .groups = 'drop') %>%
  group_by(Population_Group) %>%  # Group by population group for total calculation
  mutate(Total_Prestadores = sum(Num_Prestadores, na.rm = TRUE)) %>%
  mutate(Percentage = (Num_Prestadores / Total_Prestadores) * 100)

# Generar un gráfico de barras apiladas para mostrar la proporción de tipo de prestador por grupo de
# Generar un gráfico de barras apiladas para mostrar la proporción de tipo de prestador por grupo de población
ggplot(prestador_percentage, aes(x = Population_Group, y = Percentage, fill = Tipo_Prestador)) +
  geom_bar(stat = "identity", position = "fill") +
  theme_minimal() +
  labs(title = "Distribución de Tipos de Prestadores por Grupo de Población",
       x = "Grupo de Población",
       y = "Proporción (%)",
       fill = "Tipo de Prestador") +
  scale_y_continuous(labels = scales::percent_format())  # Formato de porcentaje en el eje y

# Generar un gráfico de barras para mostrar la distribución de clase de persona
clase_persona_distribution <- dataset_prestadores %>%
  group_by(clase_persona) %>%
  summarise(Count = n())

ggplot(clase_persona_distribution, aes(x = clase_persona, y = Count, fill = clase_persona)) +
  geom_bar(stat = "identity") +
  theme_minimal() +
  labs(title = "Distribución de Clase de Persona",
       x = "Clase de Persona",
       y = "Cantidad") +
  scale_fill_discrete(name = "Clase de Persona")

# Seleccionar las 5 ciudades más pobladas
top_5_populated_cities <- merged_data %>%
  arrange(desc(Poblacion)) %>%
  distinct(Municipio, .keep_all = TRUE) %>%
  head(5)

# Seleccionar las 5 ciudades con población menor a 500.000 más pobladas
under_500k_cities <- merged_data %>%
  filter(Poblacion < 500000) %>%
  arrange(desc(Poblacion)) %>%
  distinct(Municipio, .keep_all = TRUE) %>%
  head(5)

# Generar gráficos de dona para las 5 ciudades más pobladas
for (city in top_5_populated_cities$Municipio) {
  # Consulta para cada categoría dentro de una ciudad
  category_data_query <- sprintf("
    SELECT clpr_nombre, COUNT(*) AS Num_Prestadores
    FROM tabla_prestadores p
    JOIN tabla_municipios_clean m ON p.muni_nombre = m.Municipio_Limpio
    WHERE m.Municipio_Limpio = '%s'
    GROUP BY clpr_nombre;", city)
  
  # Obtener datos para el gráfico de dona
  category_data <- dbGetQuery(conect, category_data_query)
  
  # Gráfico para cada ciudad
  plot <- plot_ly(category_data, labels = ~clpr_nombre, values = ~Num_Prestadores, type = 'pie', hole = 0.4, textinfo = 'label+percent', insidetextorientation = 'radial', name = city) %>%
    layout(title = paste("Distribución de Tipos de Prestadores en", city, "(Más Poblada)"))
  print(plot)
}

# Generar gráficos de dona para las 5 ciudades con población menor a 500.000
for (city in under_500k_cities$Municipio) {
  # Consulta para cada categoría dentro de una ciudad
  category_data_query <- sprintf("
    SELECT clpr_nombre, COUNT(*) AS Num_Prestadores
    FROM tabla_prestadores p
    JOIN tabla_municipios_clean m ON p.muni_nombre = m.Municipio_Limpio
    WHERE m.Municipio_Limpio = '%s'
    GROUP BY clpr_nombre;", city)
  
  # Obtener datos para el gráfico de dona
  category_data <- dbGetQuery(conect, category_data_query)
  
  # Gráfico para cada ciudad
  plot <- plot_ly(category_data, labels = ~clpr_nombre, values = ~Num_Prestadores, type = 'pie', hole = 0.4, textinfo = 'label+percent', insidetextorientation = 'radial', name = city) %>%
    layout(title = paste("Distribución de Tipos de Prestadores en", city, "(Menor de 500k)"))
  print(plot)
}

# Preparar los datos para el informe
report_data <- prestador_percentage %>%
  arrange(Population_Group, desc(Percentage)) %>%
  group_by(Population_Group) %>%
  summarise(Report = paste(Tipo_Prestador, sprintf("%.2f%%", Percentage), collapse = ', '))

# Guardar el informe en un archivo de texto
write_lines <- function(text_vector, file_name) {
  cat(text_vector, file = file_name, sep = "\n")
}

# Generar el texto del informe
report_text <- paste("Reporte de Porcentaje de Tipos de Prestadores por Grupo de Población:", "\n",
                     apply(report_data, 1, function(x) paste(x[1], x[2], "\n\n")))

# Escribir el informe en un archivo .txt
write_lines(report_text, "reporte_tipos_prestadores_por_grupo_poblacion.txt")

# Imprimir mensaje de confirmación
print("El informe ha sido guardado exitosamente en 'reporte_tipos_prestadores_por_grupo_poblacion.txt'")

# Cerrar la conexión a la base de datos
dbDisconnect(conect)

