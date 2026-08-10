### Este script de PowerShell filtra los usuarios de Active Directory que tienen establecido
### el atributo "extensionAttribute15" y cuyo valor no se encuentra en una lista de valores excluidos.
### Luego, muestra los resultados en una tabla y opcionalmente los exporta a un archivo CSV.

# Comienzo del script

# Importar el modulo de Active Directory
Import-Module ActiveDirectory

# Definir una lista de valores a excluir del filtro
$excludeList = @("Valor11", "Valor2", "Valor3")

# Filtrar los usuarios de AD que tengan seteado (not null) el "extensionAttribute15" y cuyo valor no esta en la lista de excluidos.
$users = Get-ADUser -Filter {extensionAttribute15 -like "*" -and -not (extensionAttribute15 -in $excludeList)} -Properties extensionAttribute15 | 
    Select-Object SamAccountName, extensionAttribute15

# Mostrar los resultados del filtro en formato tabla.
$users | Format-Table -AutoSize

# Opcionalmente, exportar los resultados a un archivo CSV
$users | Export-Csv -Path "C:\FilteredADUsers.csv" -NoTypeInformation

Write-Host "Total de usuarios encontrados: $($users.Count)"
Write-Host "Los resultados han sido exportados a C:\Scripts\FilteredADUsers.csv"
# Fin del script