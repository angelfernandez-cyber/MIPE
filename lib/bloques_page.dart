/* import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BloquesPage extends StatelessWidget {
  const BloquesPage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF008DC5);
    const Color darkBlue = Color(0xFF005F86);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8), // Fondo suave para que resalten los bloques
      appBar: AppBar(
        title: const Text('MAPA DE BLOQUES', 
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        backgroundColor: brandBlue,
        centerTitle: true,
        elevation: 10,
        shadowColor: brandBlue.withOpacity(0.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 25, bottom: 10),
            child: Text(
              "Seleccione el área de aplicación",
              style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // Menos columnas + columnas para mejor diseño
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 1, // Cuadrados perfectos
              ),
              itemCount: 45,
              itemBuilder: (context, index) {
                int numeroBloque = index + 1;
                return _buildBloqueCard(numeroBloque, brandBlue, darkBlue);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloqueCard(int numero, Color color, Color colorDark) {
    return InkWell(
      onTap: () => Get.toNamed('/formulario', arguments: numero.toString()),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color,
              colorDark,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Icono de fondo decorativo
            Positioned(
              right: -5,
              bottom: -5,
              child: Icon(
                Icons.agriculture,
                size: 50,
                color: Colors.white.withOpacity(0.15),
              ),
            ),
            // Contenido principal
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "BLOQUE",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$numero',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} */
