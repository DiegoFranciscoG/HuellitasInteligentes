package com.huellitas.storage;

import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.client.builder.AwsClientBuilder;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import com.amazonaws.services.s3.model.CannedAccessControlList;
import com.amazonaws.services.s3.model.ObjectMetadata;
import com.amazonaws.services.s3.model.PutObjectRequest;
import com.amazonaws.HttpMethod;
import com.amazonaws.services.s3.model.GeneratePresignedUrlRequest;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.net.URL;
import java.util.Date;
import java.util.UUID;

/**
 * Sube y firma URLs de descarga para el contenido multimedia general del
 * sistema (imágenes y videos de publicaciones, códigos QR generados en el
 * servidor), almacenado en un bucket de Backblaze B2.
 */
@Service
public class S3Service {

    private final AmazonS3 s3Client;
    private final String bucketName = "AlmacenamientoVIF";
    private final String endpoint = "s3.us-east-005.backblazeb2.com";
    private final String region = "us-east-005";

    // Las llaves llegan desde application.properties, que a su vez las lee de
    // variables de entorno. Antes estaban escritas aquí y viajaban al repositorio.
    public S3Service(
            @org.springframework.beans.factory.annotation.Value("${storage.media.access-key:}") String accessKey,
            @org.springframework.beans.factory.annotation.Value("${storage.media.secret-key:}") String secretKey) {

        BasicAWSCredentials credentials = new BasicAWSCredentials(accessKey, secretKey);

        this.s3Client = AmazonS3ClientBuilder.standard()
                .withCredentials(new AWSStaticCredentialsProvider(credentials))
                .withEndpointConfiguration(new AwsClientBuilder.EndpointConfiguration("https://" + endpoint, region))
                .build();
    }

    /**
     * Sube un archivo multimedia al bucket general con un nombre único, y
     * devuelve la ruta interna de la API a través de la cual se puede
     * descargar (que a su vez redirige a una URL firmada).
     *
     * @param file archivo a subir.
     * @return la ruta interna ({@code /api/huellitas/media/...}) para descargar el archivo.
     * @throws IOException si ocurre un error leyendo el contenido del archivo.
     */
    private static final java.util.Set<String> TIPOS_PERMITIDOS = java.util.Set.of(
        "image/jpeg", "image/png", "image/webp", "image/gif",
        "video/mp4", "video/quicktime", "video/webm"
    );
    private static final java.util.Set<String> EXTENSIONES_PERMITIDAS = java.util.Set.of(
        ".jpg", ".jpeg", ".png", ".webp", ".gif", ".mp4", ".mov", ".webm"
    );

    public String uploadFile(MultipartFile file) throws IOException {
        String originalFilename = file.getOriginalFilename();
        String extension = originalFilename != null && originalFilename.contains(".") ? originalFilename.substring(originalFilename.lastIndexOf(".")).toLowerCase() : "";
        String contentType = file.getContentType();
        if (contentType == null || !TIPOS_PERMITIDOS.contains(contentType.toLowerCase()) || !EXTENSIONES_PERMITIDAS.contains(extension)) {
            throw new IllegalArgumentException("Tipo de archivo no permitido. Solo se aceptan imágenes (JPG, PNG, WEBP, GIF) y videos (MP4, MOV, WEBM).");
        }
        String key = UUID.randomUUID().toString() + extension;

        ObjectMetadata metadata = new ObjectMetadata();
        metadata.setContentType(file.getContentType());
        metadata.setContentLength(file.getSize());

        PutObjectRequest request = new PutObjectRequest(bucketName, key, file.getInputStream(), metadata);
        s3Client.putObject(request);

        // We return an internal endpoint so our backend can redirect to a pre-signed URL securely.
        return "/api/huellitas/media/" + key;
    }

    /**
     * Sube contenido que ya tenemos en memoria (por ejemplo el PNG de un QR
     * generado por el servidor, que no llega como MultipartFile).
     * Devuelve la clave del objeto, no la ruta interna, porque quien la usa
     * necesita firmar la URL con su propia caducidad.
     */
    public String uploadBytes(byte[] contenido, String contentType, String extension) {
        String key = UUID.randomUUID().toString() + extension;

        ObjectMetadata metadata = new ObjectMetadata();
        metadata.setContentType(contentType);
        metadata.setContentLength(contenido.length);

        PutObjectRequest request = new PutObjectRequest(
                bucketName, key, new java.io.ByteArrayInputStream(contenido), metadata);
        s3Client.putObject(request);

        return key;
    }

    /**
     * Genera una URL de descarga firmada y temporal (1 hora de vigencia)
     * para un objeto del bucket general.
     *
     * @param key clave del objeto dentro del bucket.
     * @return la URL firmada, válida por 1 hora.
     */
    public String generatePresignedUrl(String key) {
        return generatePresignedUrl(key, 1);
    }

    /**
     * URL firmada con caducidad a medida. El QR del correo necesita durar más
     * que la hora por defecto: si el enlace vence antes que el propio código,
     * el destinatario abre el correo y ve una imagen rota.
     */
    public String generatePresignedUrl(String key, int horasDeVida) {
        Date expiration = new Date();
        long expTimeMillis = expiration.getTime();
        expTimeMillis += 1000L * 60 * 60 * horasDeVida;
        expiration.setTime(expTimeMillis);

        GeneratePresignedUrlRequest generatePresignedUrlRequest =
                new GeneratePresignedUrlRequest(bucketName, key)
                .withMethod(HttpMethod.GET)
                .withExpiration(expiration);

        URL url = s3Client.generatePresignedUrl(generatePresignedUrlRequest);
        return url.toString();
    }

    /**
     * URL firmada con caducidad en minutos, para el objeto en sí siga sin
     * poder verse una vez que expiró en la base de datos (Momentos de tu
     * mascota: aunque alguien tenga el enlace guardado, deja de servir).
     *
     * @param key clave del objeto dentro del bucket.
     * @param minutosDeVida minutos de vigencia de la URL.
     * @return la URL firmada, válida por esos minutos.
     */
    public String generatePresignedUrlMinutos(String key, int minutosDeVida) {
        Date expiration = new Date();
        expiration.setTime(expiration.getTime() + 1000L * 60 * minutosDeVida);

        GeneratePresignedUrlRequest generatePresignedUrlRequest =
                new GeneratePresignedUrlRequest(bucketName, key)
                .withMethod(HttpMethod.GET)
                .withExpiration(expiration);

        URL url = s3Client.generatePresignedUrl(generatePresignedUrlRequest);
        return url.toString();
    }

    /**
     * Elimina un objeto del bucket general. Lo usa la limpieza de fragmentos
     * de "Momentos de tu mascota" que nunca se guardaron: ahí no basta con
     * dejar que la URL firmada caduque, hay que liberar el espacio real.
     *
     * @param key clave del objeto a borrar.
     */
    public void eliminarObjeto(String key) {
        s3Client.deleteObject(bucketName, key);
    }
}
