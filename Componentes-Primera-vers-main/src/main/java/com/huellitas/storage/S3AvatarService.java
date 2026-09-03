package com.huellitas.storage;

import com.amazonaws.HttpMethod;
import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.client.builder.AwsClientBuilder;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import com.amazonaws.services.s3.model.GeneratePresignedUrlRequest;
import com.amazonaws.services.s3.model.ObjectMetadata;
import com.amazonaws.services.s3.model.PutObjectRequest;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.URL;
import java.util.Date;
import java.util.UUID;

/**
 * Sube y firma URLs de descarga para las fotos de perfil (usuarios y
 * mascotas), almacenadas en un bucket de Backblaze B2 separado del de
 * contenido multimedia general.
 */
@Service
public class S3AvatarService {

    private final AmazonS3 s3Client;
    private final String bucketName = "ALM-FT";
    private final String endpoint = "s3.us-east-005.backblazeb2.com";
    private final String region = "us-east-005";

    // Llaves desde configuración, no escritas en el código (ver S3Service).
    public S3AvatarService(
            @org.springframework.beans.factory.annotation.Value("${storage.avatar.access-key:}") String accessKey,
            @org.springframework.beans.factory.annotation.Value("${storage.avatar.secret-key:}") String secretKey) {

        BasicAWSCredentials credentials = new BasicAWSCredentials(accessKey, secretKey);

        this.s3Client = AmazonS3ClientBuilder.standard()
                .withCredentials(new AWSStaticCredentialsProvider(credentials))
                .withEndpointConfiguration(new AwsClientBuilder.EndpointConfiguration("https://" + endpoint, region))
                .build();
    }

    /**
     * Sube una foto de perfil al bucket de avatares con un nombre único, y
     * devuelve la ruta interna de la API a través de la cual se puede
     * descargar (que a su vez redirige a una URL firmada).
     *
     * @param file archivo de imagen a subir.
     * @return la ruta interna ({@code /api/huellitas/media/avatar/...}) para descargar el archivo.
     * @throws IOException si ocurre un error leyendo el contenido del archivo.
     */
    private static final java.util.Set<String> TIPOS_PERMITIDOS = java.util.Set.of(
        "image/jpeg", "image/png", "image/webp", "image/gif"
    );
    private static final java.util.Set<String> EXTENSIONES_PERMITIDAS = java.util.Set.of(
        ".jpg", ".jpeg", ".png", ".webp", ".gif"
    );

    public String uploadFile(MultipartFile file) throws IOException {
        String originalFilename = file.getOriginalFilename();
        String extension = originalFilename != null && originalFilename.contains(".") ? originalFilename.substring(originalFilename.lastIndexOf(".")).toLowerCase() : "";
        String contentType = file.getContentType();
        if (contentType == null || !TIPOS_PERMITIDOS.contains(contentType.toLowerCase()) || !EXTENSIONES_PERMITIDAS.contains(extension)) {
            throw new IllegalArgumentException("Tipo de archivo no permitido. Solo se aceptan imágenes (JPG, PNG, WEBP, GIF).");
        }
        String key = UUID.randomUUID().toString() + extension;

        ObjectMetadata metadata = new ObjectMetadata();
        metadata.setContentType(file.getContentType());
        metadata.setContentLength(file.getSize());

        PutObjectRequest request = new PutObjectRequest(bucketName, key, file.getInputStream(), metadata);
        s3Client.putObject(request);

        // We return an internal endpoint so our backend can redirect to a pre-signed URL securely.
        return "/api/huellitas/media/avatar/" + key;
    }

    /**
     * Genera una URL de descarga firmada y temporal (1 hora de vigencia)
     * para un objeto del bucket de avatares.
     *
     * @param key clave del objeto dentro del bucket.
     * @return la URL firmada, válida por 1 hora.
     */
    public String generatePresignedUrl(String key) {
        Date expiration = new Date();
        long expTimeMillis = expiration.getTime();
        expTimeMillis += 1000 * 60 * 60; // 1 hour expiration
        expiration.setTime(expTimeMillis);

        GeneratePresignedUrlRequest generatePresignedUrlRequest = 
                new GeneratePresignedUrlRequest(bucketName, key)
                .withMethod(HttpMethod.GET)
                .withExpiration(expiration);
        
        URL url = s3Client.generatePresignedUrl(generatePresignedUrlRequest);
        return url.toString();
    }
}
