# Prueba Técnica

Este repositorio contiene la solución a la prueba técnica de análisis de datos utilizando R y SQLite, como parte del proceso de selección.

# Requisitos

La prueba ha sido desarrollada completamente en R y SQL, cumpliendo con las siguientes consideraciones:

# Desarrollo en R y SQL: 
  Todo el código fuente está escrito en R y SQL.
# Repositorio en GitHub: 
  Todos los archivos relevantes se encuentran en este repositorio.


# Ejecutar 
main_script.R en Rstudio ajustando el PATH a la ubicación local de los archivos que hayas dispuesto

README.md: Este archivo con las instrucciones y consideraciones de la prueba técnica.

Instrucciones para Ejecutar el Proyecto
Prerrequisitos
R (versión 4.0 o superior)
RStudio
SQLite

Paquetes de R: DBI, RSQLite, ggplot2, dplyr, tidyr

Instalación de Paquetes en R

install.packages(c("DBI", "RSQLite", "ggplot2", "dplyr", "tidyr"))

Cargar la Base de Datos en SQLite

Se cargaron las bases de datos compartidas en SQLite utilizando el siguiente formato:


# Conectar a SQLite
library(DBI)
con <- dbConnect(RSQLite::SQLite(), "path a la base de datos.db")

# Cargar datos
dbWriteTable(con, "nombre_tabla", data_frame)
Ejecutar Consultas SQL desde R
Ejecutar las consultas necesarias para el análisis directamente desde R:

# Ejecutar una consulta SQLite
query <- "SELECT column1, column2 FROM nombre_tabla WHERE condition;"
result <- dbGetQuery(con, query)

# Mostrar resultados
print(result)
Análisis y Visualización de Datos
Realizar análisis descriptivos y visualizaciones de los datos obtenidos:

# Cargar paquetes necesarios
library(ggplot2)
library(dplyr)
library(readxl)
library(DBI)
library(RSQLite)
library(ggplot2)
library(dplyr)
library(tidyr)
library(gdata)
library(plotly)
library(stringi)

# Ejemplo de análisis descriptivo
summary(result)

# Ejemplo de visualización

ggplot(result, aes(x = column1, y = column2)) +
  geom_point() +
  labs(title = "Título del Gráfico", x = "Eje X", y = "Eje Y")
  
Resultados

Los resultados de los análisis han sido presentados en un boletín de Word de dos páginas. Además, se ha grabado un video de máximo 3 minutos explicando los resultados obtenidos que se enviará vía correo electrónico.

Contacto
Para cualquier duda o consulta, por favor contacta a mend2atipob@gmail.com.  

 
