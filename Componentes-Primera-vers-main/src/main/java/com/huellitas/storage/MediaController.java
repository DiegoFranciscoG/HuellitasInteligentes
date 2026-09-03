package com.huellitas.storage;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;

/**
 * Sirve de puerta de entrada única para descargar archivos multimedia
 * (publicaciones, avatares) almacenados en los buckets privados de
 * Backblaze B2, redirigiendo al cliente a una URL firmada de corta
 * duración en vez de exponer las credenciales o los buckets directamente.
 */
@RestController
@RequestMapping("/api/huellitas/media")
public class MediaController {

    private final S3Service s3Service;
    private final S3AvatarService s3AvatarService;

    public MediaController(S3Service s3Service, S3AvatarService s3AvatarService) {
        this.s3Service = s3Service;
        this.s3AvatarService = s3AvatarService;
    }

    /**
     * Redirige al cliente a una URL firmada temporal para descargar un
     * archivo multimedia (imagen o video de una publicación) del bucket general.
     *
     * @param key clave del objeto dentro del bucket de almacenamiento.
     * @return una respuesta de redirección (302) hacia la URL firmada de Backblaze B2.
     */
    @GetMapping("/{key}")
    public ResponseEntity<Void> getMedia(@PathVariable String key) {
        // Generate pre-signed URL for the private bucket
        String presignedUrl = s3Service.generatePresignedUrl(key);

        // Redirect the client to download directly from Backblaze B2 using the pre-signed URL
        return ResponseEntity.status(HttpStatus.FOUND)
                .location(URI.create(presignedUrl))
                .build();
    }

    /**
     * Redirige al cliente a una URL firmada temporal para descargar una
     * foto de perfil (usuario o mascota) del bucket de avatares.
     *
     * @param key clave del objeto dentro del bucket de avatares.
     * @return una respuesta de redirección (302) hacia la URL firmada de Backblaze B2.
     */
    @GetMapping("/avatar/{key}")
    public ResponseEntity<Void> getAvatarMedia(@PathVariable String key) {
        // Generate pre-signed URL for the avatar private bucket
        String presignedUrl = s3AvatarService.generatePresignedUrl(key);

        // Redirect the client to download directly from Backblaze B2 using the pre-signed URL
        return ResponseEntity.status(HttpStatus.FOUND)
                .location(URI.create(presignedUrl))
                .build();
    }
}
