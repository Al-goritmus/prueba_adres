# Paquetes requeridos
required_packages <- c("readxl", "DBI", "RSQLite", "ggplot2", "dplyr", "tidyr", "gdata", "plotly", "stringi")

# Instalar lo que aún no tengas instalado en tu máquina para poder ejectuar el código. 

new_packages <- required_packages[!(required_packages %in% installed.packages()[, "Package"])]
if (length(new_packages) > 0) {
  install.packages(new_packages)
}
